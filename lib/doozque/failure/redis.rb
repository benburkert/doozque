module Doozque
  module Failure
    # A Failure backend that stores exceptions in Redis. Very simple but
    # works out of the box, along with support in the Doozque web app.
    class Redis < Base
      def save
        data = {
          :failed_at => Time.now.strftime("%Y/%m/%d %H:%M:%S"),
          :payload   => payload,
          :exception => exception.class.to_s,
          :error     => exception.to_s,
          :backtrace => filter_backtrace(Array(exception.backtrace)),
          :worker    => worker.to_s,
          :queue     => queue
        }
        data = Doozque.encode(data)
        Doozque.redis.rpush(:failed, data)
      end

      def self.count
        raw = Doozque.fraggle.get('/stat/failed').value
        raw.empty? ? 0 : raw.to_i
      end

      def self.all(start = 0, count = 1)
        Doozque.list_range(:failed, start, count)
      end

      def self.clear
        Doozque.fraggle.del('/stat/failed')
      end

      def self.requeue(index)
        item = all(index)
        item['retried_at'] = Time.now.strftime("%Y/%m/%d %H:%M:%S")
        Doozque.redis.lset(:failed, index, Doozque.encode(item))
        Job.create(item['queue'], item['payload']['class'], *item['payload']['args'])
      end

      def self.remove(index)
        id = rand(0xffffff)
        Doozque.redis.lset(:failed, index, id)
        Doozque.redis.lrem(:failed, 1, id)
      end

      def filter_backtrace(backtrace)
        index = backtrace.index { |item| item.include?('/lib/doozque/job.rb') }
        backtrace.first(index.to_i)
      end
    end
  end
end
