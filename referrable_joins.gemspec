# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "referrable_joins/version"

Gem::Specification.new do |s|
  s.name        = "referrable_joins"
  s.version     = ReferrableJoins::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Burke Libbey"]
  s.email       = ["burke@burkelibbey.org"]
  s.homepage    = ""
  s.summary     = %q{Adds the ability to refer to columns in a specific auto-generated join using the Arel::Table class}
  s.description = %q{Adds the ability to refer to columns in a specific auto-generated join using the Arel::Table class}

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
