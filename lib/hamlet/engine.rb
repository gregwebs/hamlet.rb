class Hamlet::Engine < Slim::Engine
  replace Slim::Parser, Hamlet::Parser
end
