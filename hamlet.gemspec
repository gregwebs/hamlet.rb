# -*- encoding: utf-8 -*-
#require File.dirname(__FILE__) + '/lib/hamlet/version'
require 'date'

Gem::Specification.new do |s|
  s.name              = 'hamlet'
  s.version           = '0.4.1'
  s.date              = Date.today.to_s
  s.authors           = ['Greg Weber']
  s.email             = ['greg@gregweber.info']
  s.summary           = 'Hamlet is a DRY HTML template language.'
  s.description       = 'Hamlet is a template language whose goal is reduce HTML syntax to the essential parts.'
  s.homepage          = 'http://github.com/gregwebs/hamlet.rb'
  s.extra_rdoc_files  = %w(README.md)
  s.rdoc_options      = %w(--charset=UTF-8)
  s.rubyforge_project = s.name

  s.files         = `git ls-files`.split("\n")
  #s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = %w(lib)

  s.add_dependency('slim', ['~> 1.0.0'])

  s.add_development_dependency('rake', ['>= 0.8.7'])
  s.add_development_dependency('sass', ['>= 3.1.0'])
  s.add_development_dependency('minitest', ['>= 0'])
  s.add_development_dependency('kramdown', ['>= 0'])
  s.add_development_dependency('yard', ['>= 0'])
  s.add_development_dependency('creole', ['>= 0'])
  s.add_development_dependency('builder', ['>= 0'])
  s.add_development_dependency('pry', ['>= 0'])
  if RUBY_VERSION =~ /1.9/
    s.add_development_dependency('ruby-debug19', ['>= 0'])
  end

  unless defined?(RUBY_ENGINE) && RUBY_ENGINE == 'rbx'
    s.add_development_dependency('rcov', ['>= 0'])
  end
end
