require 'slim'
require 'parser'

class Hamlet::Engine < Slim::Engine
  replace Slim::Parser, Hamlet::Parser
end
