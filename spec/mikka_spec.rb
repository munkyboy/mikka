require_relative 'spec_helper'

describe Mikka do
  let(:test_actor) do
    Class.new(Mikka::Actor) do
      def self.initial_value_set(*args); end
      def initialize(*args)
        self.class.initial_value_set(*args) unless args.empty?
        super()
      end

      def receive(msg)
        sender << msg
      end
    end
  end

  let(:system) { Mikka.create_actor_system('testsystem') }
  after { system.shutdown }

  describe 'actor creation' do
    it 'creates an actor from a class' do
      actor_props = Mikka::Props[test_actor]
      actor = system.actor_of(actor_props, 'some_actor')
      actor.should be_a(Akka::Actor::ActorRef)
    end

    it 'passes arguments to the actor contructor' do
      test_actor.should_receive(:initial_value_set).with(:a, 1)
      actor_props = Mikka::Props[test_actor, :a, 1]
      actor = system.actor_of(actor_props, 'some_actor')
      actor.should be_a(Akka::Actor::ActorRef)
      sleep 0.2
    end
  end

  describe 'message sending' do
    shared_examples "sending tests" do
      describe '#tell/#<<' do
        it 'sends a message to an actor' do
          actor << 'hello'
        end
      end

      describe '#ask' do
        it 'sends a message' do
          future = actor.ask(:hi)
          reply = Mikka.await_result(future)
          reply.should == :hi
        end
      end

      describe '#ask_and_wait' do
        it 'sends a message then waits' do
          expect(actor.ask_and_wait(:hi)).to eq :hi
        end
      end

      describe "pipe_to" do
        let(:reverser_actor) do
          Class.new(Mikka::Actor) do
            def receive(msg)
              sender << self.class.reverse_it(msg)
            end

            def self.reverse_it(v)
            end
          end
        end
        let(:reverser) { system.actor_of(Mikka::Props[reverser_actor], 'reverser_actor') }

        it "sends to another actor" do
          reverser_actor.should_receive(:reverse_it).with('pipe').and_return('epipe')
          actor.ask('pipe').pipe_to(reverser)
          sleep 0.2
        end
      end
    end

    context "using an actorRef" do
      let(:actor) { system.actor_of(Mikka::Props[test_actor], 'test_actor') }
      include_examples "sending tests"
    end

    context "using an actorSelection" do
      let(:actor) { system.actor_of(Mikka::Props[test_actor], 'test_actor'); system.actor_selection('akka://testsystem/user/test_actor') }
      include_examples "sending tests"
    end
  end

  describe 'supervision' do
    let(:callback_logging_methods) do
      Module.new do
        def self.extended(k)
          k.send(:include, InstanceMethods)
        end

        module InstanceMethods
          def post_stop
            self.class.log_post_stop
          end
          def post_restart(reason)
            self.class.log_post_restart reason.exception
          end
        end

        def log_post_stop; end
        def log_post_restart(e); end
      end
    end

    let(:worker) do
      Class.new(Mikka::Actor) do
        attr_accessor :stored_value
        def receive(v)
          case v
          when :raise_escalate then raise ArgumentError
          when :raise_stop then raise IndexError
          when :raise_restart then raise NoMethodError
          when :raise_resume then raise RangeError
          when :get
            sender << stored_value
          else
            self.stored_value = v
          end
        end
      end.extend callback_logging_methods
    end

    let(:supervisor) do
      Class.new(Mikka::Actor) do
        set_supervisor_strategy(:one_for_one) do |e|
          case e.exception
          when ArgumentError then :escalate
          when IndexError then :stop
          when NoMethodError then :restart
          when RangeError then :resume
          end
        end

        def receive(v)
          sender << context.actor_of(v, 'worker')
        end
      end.extend callback_logging_methods
    end

    let(:supervisor_ref) { system.actor_of(Mikka::Props[supervisor], 'supervisor') }
    let(:worker_ref) { Mikka.await_result supervisor_ref.ask(Mikka::Props[worker]) }

    it "handles an escalate policy" do
      worker_ref << :raise_escalate
      # escalation will restart the supervisor
      supervisor.should_receive(:log_post_restart).with(an_instance_of(ArgumentError))
      sleep 0.5
    end

    it "handles a stop policy" do
      worker_ref << :raise_stop
      worker.should_receive(:log_post_stop)
      sleep 0.5
    end

    it "handles a restart policy" do
      worker_ref << :raise_restart
      worker.should_receive(:log_post_restart).with(an_instance_of(NoMethodError))
      sleep 0.5
    end

    it "handles a resume policy" do
      worker_ref << 'myval'
      worker_ref << :raise_resume
      Mikka.await_result(worker_ref.ask(:get)).should == 'myval'
    end
  end

  describe 'routing helpers' do
    it "creates a round robin router with specified number of instances" do
      pending("need to figure out how best to test number of routees")
      system.actor_of(Mikka::Props[test_actor].with_round_robin_router(2))
    end

    it "creates a smallest mailbox router with specified number of instances" do
      pending("need to figure out how best to test number of routees")
      system.actor_of(Mikka::Props[test_actor].with_smallest_mailbox_router(3))
    end
  end

  describe "routed actor helpers" do
    shared_examples "helper tests" do
      describe "#current_routees" do
        it "returns list of routees" do
          expect(subject.current_routees).to have_exactly(2).items
          expect(subject.current_routees.first).to be_a Akka::Actor::ActorRef
        end
      end
    end

    let!(:actor_ref) { system.actor_of(Mikka::Props[test_actor].with_round_robin_router(2), 'routed') }

    context "with a routed actor ref" do
      subject { actor_ref }
      include_examples "helper tests"
    end

    context "with an actor selection" do
      subject { system.actor_selection('akka://testsystem/user/routed') }
      include_examples "helper tests"
    end
  end
end
