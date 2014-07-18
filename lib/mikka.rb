# encoding: utf-8

require 'akka'

module Mikka
  def self.create_actor_system(*args)
    Akka::Actor::ActorSystem.create(*args)
  end

  def self.await_result(future, timeout = '1s')
    Akka::Dispatch::Await.result(future, Duration[timeout])
  end

  Props = Akka::Actor::Props
  Duration = Akka::Util::Duration
  Timeout = Akka::Util::Timeout
  Terminated = Akka::Actor::Terminated

  class Props
    def self.[](*args, &block)
      options = args.last.is_a?(Hash) && args.pop
      creator = ((args.first.is_a?(Proc) || args.first.is_a?(Class)) && args.first) || (options && options[:creator]) || block
      raise ArgumentError, %(No creator specified) unless creator
      props = new
      props = props.with_creator(creator)
      props
    end

    class << self
      alias_method :create, :[]
    end
  end

  class Duration
    class << self
      alias_method :[], :apply
    end
  end

  module ActorSendMethods
    def <<(msg)
      tell(msg, ImplicitSender.current_actor)
    end

    def ask(value, timeout = '1s')
      Akka::Pattern::Patterns.ask(self, value, Java::AkkaUtil::Timeout.duration_to_timeout(Duration[timeout]))
    end
  end
  Akka::Actor::ActorRef.send(:include, ActorSendMethods)
  Akka::Actor::ActorSelection.send(:include, ActorSendMethods)

  module RubyesqueActorCallbacks
    def receive(message); end
    def pre_start; end
    def post_stop; end
    def pre_restart(reason, message); end
    def post_restart(reason); end

    def onReceive(message); receive(message); end
    def supervisorStrategy; supervisor_strategy; end
    def preStart; super; pre_start; end
    def postStop; super; post_stop; end
    def preRestart(reason, message_option)
      super
      pre_restart(reason, message_option.is_defined ? message_option.get : nil)
    end
    def postRestart(reason); super; post_restart(reason); end
  end

  module ImplicitSender
    class << self
      def current_actor=(actor)
        Thread.current[:mikka_current_actor] = actor
      end

      def current_actor
        Thread.current[:mikka_current_actor]
      end

      def capture_current_actor(ref)
        self.current_actor = ref
        yield
      ensure
        self.current_actor = nil
      end
    end

    [:onReceive, :preStart, :postStop, :preRestart, :postRestart].each do |meth|
      define_method(meth) do |*args|
        ImplicitSender.capture_current_actor(get_self) { super }
      end
    end
  end

  class Actor < Akka::Actor::UntypedActor
    include RubyesqueActorCallbacks
    include ImplicitSender

    class << self
      alias_method :apply, :new
      alias_method :create, :new
    end

    def self.set_supervisor_strategy(strategy, opts = {}, &block)
      max_number_of_retries = opts.fetch(:max_retries, 1)
      within_time_range = opts.fetch(:within, '1s')
      klass = case strategy
      when :all_for_one then AllForOneStrategy
      when :one_for_one then OneForOneStrategy
      else
        if strategy < Java::AkkaActor::SupervisorStrategy
          strategy
        else
          raise 'unknown strategy'
        end
      end
      s = klass.new(max_number_of_retries, within_time_range, &block)
      define_method(:supervisor_strategy) { s }
    end
  end

  module PropsConstructor
    def Props(&block)
      Props.create(&block)
    end
  end

  module Useful
    include PropsConstructor
    extend PropsConstructor

    Props = ::Mikka::Props
  end

  module SupervisionDecider
    class DeciderAdapter
      include Akka::Japi::Function
      def initialize(&block)
        @apply_block = block
      end
      def apply(e)
        # SupervisorStrategy defines methods :escalate, :stop, :restart, :resume
        Akka::Actor::SupervisorStrategy.send(@apply_block.call(e))
      end
    end
  end

  class AllForOneStrategy < Akka::Actor::AllForOneStrategy
    # Constructor expects a block taking 1 argument for exception
    # and returning :escalate, :stop, :restart, or :resume
    def initialize(max_number_of_retries, within_time_range, &block)
      super(max_number_of_retries, Duration[within_time_range], SupervisionDecider::DeciderAdapter.new(&block))
    end
  end

  class OneForOneStrategy < Akka::Actor::OneForOneStrategy
    # Constructor expects a block taking 1 argument for exception
    # and returning :escalate, :stop, :restart, or :resume
    def initialize(max_number_of_retries, within_time_range, &block)
      super(max_number_of_retries, Duration[within_time_range], SupervisionDecider::DeciderAdapter.new(&block))
    end
  end

  module FutureMethods
    def pipe_to(actor_ref)
      Akka::Pattern::Patterns.pipe(self, actor_ref.dispatcher).to(actor_ref)
    end
  end
  Java::ScalaConcurrent::Future.send(:include, FutureMethods)
end
