# encoding: utf-8

require 'java'
require 'akka'


module Mikka
  import java.util.Arrays
  
  def self.actor_of(*args, &block)
    Akka::Actor::Actors.actor_of(*args, &block)
  end
  
  def self.actor(&block)
    Akka::Actor::Actors.actor_of { ProcActor.new(&block) }
  end
  
  def self.registry
    Akka::Actor::Actors.registry
  end
  
  module Messages
    def self.broadcast(message)
      Akka::Routing::Routing::Broadcast.new(message)
    end
  
    def self.poison_pill
      Akka::Actor::Actors.poison_pill
    end
  end
  
  module RubyesqueActorCallbacks
    def receive(message); end
    def pre_start; end
    def post_stop; end
    def pre_restart(reason); end
    def post_restart(reason); end
    
    def onReceive(message); receive(message); end
    def preStart; super; pre_start; end
    def postStop; super; post_stop; end
    def preRestart(reason); super; pre_restart(reason); end
    def postRestart(reason); super; post_restart(reason); end
  end
  
  class Actor < Akka::Actor::UntypedActor
    include RubyesqueActorCallbacks
  end
  
  class ProcActor < Actor
    def initialize(&receive)
      define_singleton_method(:receive, receive)
    end
  end
  
  def self.load_balancer(options={})
    actors = options[:actors]
    unless actors
      type = options[:type]
      count = options[:count]
      raise ArgumentError, "Either :actors or :type and :count must be specified" unless type && count
      actors = (0...count).map { actor_of(type) }
    end
    actor_list = Arrays.as_list(actors.map { |a| a.start }.to_java)
    actor_seq = Akka::Routing::CyclicIterator.new(actor_list)
    actor_factory = proc { actor_seq }.to_function
    Akka::Routing::Routing.load_balancer_actor(actor_factory)
  end
end
