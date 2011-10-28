module Hamlet
  # Tilt template implementation for Hamlet
  # @api public
  Template = Temple::Templates::Tilt(Hamlet::Engine, :register_as => :hamlet)

  if Object.const_defined?(:Rails)
    # Rails template implementation for Hamlet
    # @api public
    RailsTemplate = Temple::Templates::Rails(Hamlet::Engine,
                                             :register_as => :hamlet,
                                             # Use rails-specific generator. This is necessary
                                             # to support block capturing and streaming.
                                             :generator => Temple::Generators::RailsOutputBuffer,
                                             # Disable the internal hamlet capturing.
                                             # Rails takes care of the capturing by itself.
                                             :disable_capture => true,
                                             :streaming => Object.const_defined?(:Fiber))
  end
end
