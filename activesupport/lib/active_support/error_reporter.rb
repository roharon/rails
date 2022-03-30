# frozen_string_literal: true

module ActiveSupport
  # +ActiveSupport::ErrorReporter+ is a common interface for error reporting services.
  #
  # To rescue and report any unhandled error, you can use the +handle+ method:
  #
  #   Rails.error.handle do
  #     do_something!
  #   end
  #
  # If an error is raised, it will be reported and swallowed.
  #
  # Alternatively if you want to report the error but not swallow it, you can use +record+
  #
  #   Rails.error.record do
  #     do_something!
  #   end
  #
  # Both methods can be restricted to only handle a specific exception class
  #
  #   maybe_tags = Rails.error.handle(Redis::BaseError) { redis.get("tags") }
  #
  # You can also pass some extra context information that may be used by the error subscribers:
  #
  #   Rails.error.handle(context: { section: "admin" }) do
  #     # ...
  #   end
  #
  # Additionally a +severity+ can be passed along to communicate how important the error report is.
  # +severity+ can be one of +:error+, +:warning+, or +:info+. Handled errors default to the +:warning+
  # severity, and unhandled ones to +:error+.
  #
  # Both +handle+ and +record+ pass through the return value from the block. In the case of +handle+
  # rescuing an error, a fallback can be provided. The fallback must be a callable whose result will
  # be returned when the block raises and is handled:
  #
  #   user = Rails.error.handle(fallback: -> { User.anonymous }) do
  #     User.find_by(params)
  #   end
  class ErrorReporter
    SEVERITIES = %i(error warning info)

    attr_accessor :logger

    def initialize(*subscribers, logger: nil)
      @subscribers = subscribers.flatten
      @logger = logger
    end

    # Report any unhandled exception, and swallow it.
    #
    #   Rails.error.handle do
    #     1 + '1'
    #   end
    #
    def handle(error_class = StandardError, severity: :warning, context: {}, fallback: nil)
      yield
    rescue error_class => error
      report(error, handled: true, severity: severity, context: context)
      fallback.call if fallback
    end

    def record(error_class = StandardError, severity: :error, context: {})
      yield
    rescue error_class => error
      report(error, handled: false, severity: severity, context: context)
      raise
    end

    # Register a new error subscriber. The subscriber must respond to
    #
    #   report(Exception, handled: Boolean, context: Hash)
    #
    # The +report+ method +should+ never raise an error.
    def subscribe(subscriber)
      unless subscriber.respond_to?(:report)
        raise ArgumentError, "Error subscribers must respond to #report"
      end
      @subscribers << subscriber
    end

    # Prevent a subscriber from being notified of errors for the
    # duration of the block.
    #
    # It can be used by error reporting service integration when they wish
    # to handle the error higher in the stack.
    def disable(subscriber)
      disabled_subscribers = (ActiveSupport::IsolatedExecutionState[self] ||= [])
      disabled_subscribers << subscriber
      begin
        yield
      ensure
        disabled_subscribers.delete(subscriber)
      end
    end

    # Update the execution context that is accessible to error subscribers
    #
    #   Rails.error.set_context(section: "checkout", user_id: @user.id)
    #
    # See +ActiveSupport::ExecutionContext.set+
    def set_context(...)
      ActiveSupport::ExecutionContext.set(...)
    end

    # When the block based +handle+ and +record+ methods are not suitable, you can directly use +report+
    #
    #   Rails.error.report(error)
    def report(error, handled: true, severity: handled ? :warning : :error, context: {})
      unless SEVERITIES.include?(severity)
        raise ArgumentError, "severity must be one of #{SEVERITIES.map(&:inspect).join(", ")}, got: #{severity.inspect}"
      end

      full_context = ActiveSupport::ExecutionContext.to_h.merge(context)
      disabled_subscribers = ActiveSupport::IsolatedExecutionState[self]
      @subscribers.each do |subscriber|
        unless disabled_subscribers&.any? { |s| s === subscriber }
          subscriber.report(error, handled: handled, severity: severity, context: full_context)
        end
      rescue => subscriber_error
        if logger
          logger.fatal(
            "Error subscriber raised an error: #{subscriber_error.message} (#{subscriber_error.class})\n" +
            subscriber_error.backtrace.join("\n")
          )
        else
          raise
        end
      end

      nil
    end
  end
end
