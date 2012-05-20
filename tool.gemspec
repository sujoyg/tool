# -*- encoding: utf-8 -*-
require File.expand_path("../lib/tool/version", __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Sujoy Gupta"]
  gem.email         = ["sujoy@pingbooth.com"]
  gem.description   = %q{A command line tool for RDS.}
  gem.summary       = %q{This is a command line tool for performing common RDS operations.}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "tool"
  gem.require_paths = ["lib"]
  gem.version       = Tool::VERSION

  gem.add_dependency "guid"
  gem.add_development_dependency "rspec"
end
