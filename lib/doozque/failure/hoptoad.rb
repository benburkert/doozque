begin
  require 'hoptoad_notifier'
rescue LoadError
  raise "Can't find 'hoptoad_notifier' gem. Please add it to your Gemfile or install it."
end

module Doozque
  module Failure
    # A Failure backend that sends exceptions raised by jobs to Hoptoad.
    #
    # To use it, put this code in an initializer, Rake task, or wherever:
    #
    #   require 'doozque/failure/hoptoad'
    #
    #   Doozque::Failure::Multiple.classes = [Doozque::Failure::Redis, Doozque::Failure::Hoptoad]
    #   Doozque::Failure.backend = Doozque::Failure::Multiple
    #
    # Once you've configured doozque to use the Hoptoad failure backend,
    # you'll want to setup an initializer to configure the Hoptoad.
    #
    # HoptoadNotifier.configure do |config|
    #   config.api_key = 'your_key_here'
    # end
    # For more information see https://github.com/thoughtbot/hoptoad_notifier
    class Hoptoad < Base
      def self.configure(&block)
        Doozque::Failure.backend = self
        HoptoadNotifier.configure(&block)
      end

      def self.count
        # We can't get the total # of errors from Hoptoad so we fake it
        # by asking Doozque how many errors it has seen.
        Stat[:failed]
      end

      def save
        HoptoadNotifier.notify_or_ignore(exception,
          :parameters => {
            :payload_class => payload['class'].to_s,
            :payload_args => payload['args'].inspect
          }
        )
      end

    end
  end
end
