require 'fraggle/block'

require 'doozque/version'

require 'doozque/errors'

require 'doozque/failure'
require 'doozque/failure/base'

require 'doozque/helpers'
require 'doozque/stat'
require 'doozque/job'
require 'doozque/worker'
require 'doozque/plugin'

module Doozque
  include Helpers
  extend self

  def fraggle
    @fraggle ||= Fraggle::Block.connect
  end

  def doozer_id
    fraggle.to_s
  end

  # The `before_first_fork` hook will be run in the **parent** process
  # only once, before forking to run the first job. Be careful- any
  # changes you make will be permanent for the lifespan of the
  # worker.
  #
  # Call with a block to set the hook.
  # Call with no arguments to return the hook.
  def before_first_fork(&block)
    block ? (@before_first_fork = block) : @before_first_fork
  end

  # Set a proc that will be called in the parent process before the
  # worker forks for the first time.
  def before_first_fork=(before_first_fork)
    @before_first_fork = before_first_fork
  end

  # The `before_fork` hook will be run in the **parent** process
  # before every job, so be careful- any changes you make will be
  # permanent for the lifespan of the worker.
  #
  # Call with a block to set the hook.
  # Call with no arguments to return the hook.
  def before_fork(&block)
    block ? (@before_fork = block) : @before_fork
  end

  # Set the before_fork proc.
  def before_fork=(before_fork)
    @before_fork = before_fork
  end

  # The `after_fork` hook will be run in the child process and is passed
  # the current job. Any changes you make, therefore, will only live as
  # long as the job currently being processed.
  #
  # Call with a block to set the hook.
  # Call with no arguments to return the hook.
  def after_fork(&block)
    block ? (@after_fork = block) : @after_fork
  end

  # Set the after_fork proc.
  def after_fork=(after_fork)
    @after_fork = after_fork
  end

  def to_s
    "Doozer Client connected to #{doozer_id}"
  end

  # If 'inline' is true Doozque will call #perform method inline
  # without queuing it into Redis and without any Doozque callbacks.
  # The 'inline' is false Doozque jobs will be put in queue regularly.
  def inline?
    @inline
  end
  alias_method :inline, :inline?

  def inline=(inline)
    @inline = inline
  end

  #
  # queue manipulation
  #

  # Pushes a job onto a queue. Queue name should be a string and the
  # item should be any JSON-able Ruby object.
  #
  # Doozque works generally expect the `item` to be a hash with the following
  # keys:
  #
  #   class - The String name of the job to run.
  #    args - An Array of arguments to pass the job. Usually passed
  #           via `class.to_class.perform(*args)`.
  #
  # Example
  #
  #   Doozque.push('archive', :class => 'Archive', :args => [ 35, 'tar' ])
  #
  # Returns nothing
  def push(queue, item)
    watch_queue(queue)
    fraggle.set("/queue/#{queue}/#{$$}.#{Time.now.to_f}/job", encode(item))
  end

  # Pops a job off a queue. Queue name should be a string.
  #
  # Returns a Ruby object.
  def pop(queue)
    pop_existing(queue) || pop_incoming(queue)
  end

  def pop_existing(queue, offset = 0)
    response = fraggle.walk("/queue/#{queue}/*/job", offset)

    return if response.nil?

    race_for(response, queue) || pop_existing(queue, offset + 1)
  end

  def pop_incoming(queue)
    response = fraggle.wait("/queue/#{queue}/*/job")

    race_for(response, queue)
  end

  def self.race_for(response, queue)
    lock_path = response.path.sub(%r{/job$}, '/lock')
    lock_response = fraggle.get(lock_path)

    # lock doesn't exist, so race for it. If set returns nil, we lost.
    if lock_response.value.empty? && fraggle.set(lock_path, Time.now.to_s, lock_response.rev)
      fraggle.del(response.path)
      fraggle.del(lock_path)
      decode(response.value)
    end
  end

  # Returns an integer representing the size of a queue.
  # Queue name should be a string.
  def size(queue)
    fraggle.walk_all("/queue/#{queue}/*/job").size
  end

  # Returns an array of items currently queued. Queue name should be
  # a string.
  #
  # start and count should be integer and can be used for pagination.
  # start is the item to begin, count is how many items to return.
  #
  # To get the 3rd page of a 30 item, paginatied list one would use:
  #   Doozque.peek('my_list', 59, 30)
  def peek(queue, start = 0, count = 1)
    list_range("queue:#{queue}", start, count)
  end

  # Does the dirty work of fetching a range of items from a Redis list
  # and converting them into Ruby objects.
  def list_range(key, start = 0, count = 1)
    if count == 1
      decode redis.lindex(key, start)
    else
      Array(redis.lrange(key, start, start+count-1)).map do |item|
        decode item
      end
    end
  end

  # Returns an array of all known Doozque queues as strings.
  def queues
    queue_response = fraggle.get('/queues')

    if queue_response.value.empty?
      []
    else
      decode(queue_response.value)
    end
  end

  # Given a queue name, completely deletes the queue.
  def remove_queue(queue)
    queue_response = fraggle.get('/queues')
    unless queue_response.nil?
      queues = decode(queue_response.value)
      queues -= [queue]

      fraggle.set('/queues', encode(queues), queue_response.rev)
    end

    fraggle.del("/queue/#{queue}")
  end

  # Used internally to keep track of which queues we've created.
  # Don't call this directly.
  def watch_queue(queue)
    queue_response = fraggle.get('/queues')

    if queue_response.value.empty?
      queues = [queue]
    else
      queues = decode(queue_response.value)
      queues << queue unless queues.include?(queue.to_s)
    end

    fraggle.set('/queues', encode(queues), queue_response.rev)
  end

  #
  # job shortcuts
  #

  # This method can be used to conveniently add a job to a queue.
  # It assumes the class you're passing it is a real Ruby class (not
  # a string or reference) which either:
  #
  #   a) has a @queue ivar set
  #   b) responds to `queue`
  #
  # If either of those conditions are met, it will use the value obtained
  # from performing one of the above operations to determine the queue.
  #
  # If no queue can be inferred this method will raise a `Doozque::NoQueueError`
  #
  # This method is considered part of the `stable` API.
  def enqueue(klass, *args)
    # Perform before_enqueue hooks. Don't perform enqueue if any hook returns false
    before_hooks = Plugin.before_enqueue_hooks(klass).collect do |hook|
      klass.send(hook, *args)
    end
    return if before_hooks.any? { |result| result == false }

    Job.create(queue_from_class(klass), klass, *args)

    Plugin.after_enqueue_hooks(klass).each do |hook|
      klass.send(hook, *args)
    end
  end

  # This method can be used to conveniently remove a job from a queue.
  # It assumes the class you're passing it is a real Ruby class (not
  # a string or reference) which either:
  #
  #   a) has a @queue ivar set
  #   b) responds to `queue`
  #
  # If either of those conditions are met, it will use the value obtained
  # from performing one of the above operations to determine the queue.
  #
  # If no queue can be inferred this method will raise a `Doozque::NoQueueError`
  #
  # If no args are given, this method will dequeue *all* jobs matching
  # the provided class. See `Doozque::Job.destroy` for more
  # information.
  #
  # Returns the number of jobs destroyed.
  #
  # Example:
  #
  #   # Removes all jobs of class `UpdateNetworkGraph`
  #   Doozque.dequeue(GitHub::Jobs::UpdateNetworkGraph)
  #
  #   # Removes all jobs of class `UpdateNetworkGraph` with matching args.
  #   Doozque.dequeue(GitHub::Jobs::UpdateNetworkGraph, 'repo:135325')
  #
  # This method is considered part of the `stable` API.
  def dequeue(klass, *args)
    Job.destroy(queue_from_class(klass), klass, *args)
  end

  # Given a class, try to extrapolate an appropriate queue based on a
  # class instance variable or `queue` method.
  def queue_from_class(klass)
    klass.instance_variable_get(:@queue) ||
      (klass.respond_to?(:queue) and klass.queue)
  end

  # This method will return a `Doozque::Job` object or a non-true value
  # depending on whether a job can be obtained. You should pass it the
  # precise name of a queue: case matters.
  #
  # This method is considered part of the `stable` API.
  def reserve(queue)
    Job.reserve(queue)
  end

  # Validates if the given klass could be a valid Doozque job
  #
  # If no queue can be inferred this method will raise a `Doozque::NoQueueError`
  #
  # If given klass is nil this method will raise a `Doozque::NoClassError`
  def validate(klass, queue = nil)
    queue ||= queue_from_class(klass)

    if !queue
      raise NoQueueError.new("Jobs must be placed onto a queue.")
    end

    if klass.to_s.empty?
      raise NoClassError.new("Jobs must be given a class.")
    end
  end


  #
  # worker shortcuts
  #

  # A shortcut to Worker.all
  def workers
    Worker.all
  end

  # A shortcut to Worker.working
  def working
    Worker.working
  end

  # A shortcut to unregister_worker
  # useful for command line tool
  def remove_worker(worker_id)
    worker = Doozque::Worker.find(worker_id)
    worker.unregister_worker
  end

  #
  # stats
  #

  # Returns a hash, similar to redis-rb's #info, of interesting stats.
  def info
    return {
      :pending   => queues.inject(0) { |m,k| m + size(k) },
      :processed => Stat[:processed],
      :queues    => queues.size,
      :workers   => workers.size.to_i,
      :working   => working.size,
      :failed    => Stat[:failed],
      :servers   => [doozer_id],
      :environment  => ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
    }
  end

  # Returns an array of all known Doozque keys in Redis. Redis' KEYS operation
  # is O(N) for the keyspace, so be careful - this can be slow for big databases.
  def keys
    fraggle.walk_all('/**').map {|r| r.path }
  end
end

