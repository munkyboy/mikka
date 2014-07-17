require_relative 'spec_helper'

module Mikka
  class TestActor < Mikka::Actor
    def receive(msg)
      sender << msg
    end
  end

  describe 'actor creation' do
    before do
      @system = Mikka.create_actor_system('testsystem')
    end

    after do
      @system.shutdown
    end

    it 'creates an actor from a class' do
      actor_props = Props[TestActor]
      actor = @system.actor_of(actor_props, 'some_actor')
      actor.should be_a(ActorRef)
    end

    it 'creates an actor from a factory proc' do
      actor_props = Props[:creator => proc { TestActor.new }]
      actor = @system.actor_of(actor_props, 'some_actor')
      actor.should be_a(ActorRef)
    end

    it 'creates an actor from a factory block' do
      actor_props = Props.create { TestActor.new }
      actor = @system.actor_of(actor_props, 'some_actor')
      actor.should be_a(ActorRef)
    end

    it 'creates an actor from a factory block passed to the Props function' do
      actor_props = Useful.Props { TestActor.new }
      actor = @system.actor_of(actor_props, 'some_actor')
      actor.should be_a(ActorRef)
    end
  end

  describe 'message sending' do
    before do
      @system = Mikka.create_actor_system('testsystem')
      @actor = @system.actor_of(Props[TestActor])
    end

    after do
      @system.shutdown
    end

    describe '#tell/#<<' do
      it 'sends a message to an actor' do
        @actor << 'hello'
      end
    end

    describe '#ask' do
      it 'sends a message' do
        future = @actor.ask(:hi)
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
      let(:reverser) { @system.actor_of(Props[reverser_actor], 'reverser_actor') }

      it "sends to another actor" do
        reverser_actor.should_receive(:reverse_it).with('pipe').and_return('epipe')
        @actor.ask('pipe').pipe_to(reverser)
        sleep 0.2
      end
    end
  end
end
