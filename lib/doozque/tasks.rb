# require 'doozque/tasks'
# will give you the doozque tasks

namespace :doozque do
  task :setup

  desc "Start a Doozque worker"
  task :work => :setup do
    require 'doozque'

    queues = (ENV['QUEUES'] || ENV['QUEUE']).to_s.split(',')

    begin
      worker = Doozque::Worker.new(*queues)
      worker.verbose = ENV['LOGGING'] || ENV['VERBOSE']
      worker.very_verbose = ENV['VVERBOSE']
    rescue Doozque::NoQueueError
      abort "set QUEUE env var, e.g. $ QUEUE=critical,high rake doozque:work"
    end

    if ENV['PIDFILE']
      File.open(ENV['PIDFILE'], 'w') { |f| f << worker.pid }
    end

    worker.log "Starting worker #{worker}"

    worker.work(ENV['INTERVAL'] || 5) # interval, will block
  end

  desc "Start multiple Doozque workers. Should only be used in dev mode."
  task :workers do
    threads = []

    ENV['COUNT'].to_i.times do
      threads << Thread.new do
        system "rake doozque:work"
      end
    end

    threads.each { |thread| thread.join }
  end
end
