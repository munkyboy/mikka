require_relative 'spec_helper'

describe Mikka do
  let(:test_actor) do
    Class.new(Mikka::Actor) do
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
      actor.should be_a(Mikka::ActorRef)
    end

    it 'creates an actor from a factory proc' do
      actor_props = Mikka::Props[:creator => proc { test_actor.new }]
      actor = system.actor_of(actor_props, 'some_actor')
      actor.should be_a(Mikka::ActorRef)
    end

    it 'creates an actor from a factory block' do
      actor_props = Mikka::Props.create { test_actor.new }
      actor = system.actor_of(actor_props, 'some_actor')
      actor.should be_a(Mikka::ActorRef)
    end

    it 'creates an actor from a factory block passed to the Mikka::Props function' do
      actor_props = Mikka::Useful.Props { test_actor.new }
      actor = system.actor_of(actor_props, 'some_actor')
      actor.should be_a(Mikka::ActorRef)
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
end
