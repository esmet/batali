# -*- encoding: utf-8 -*-
require File.expand_path('../lib/batali/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["John Esmet"]
  gem.email         = ["john.esmet@gmail.com"]
  gem.description   = %q{TODO: Write a gem description}
  gem.summary       = %q{TODO: Write a gem summary}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "batali"
  gem.require_paths = ["lib"]
  gem.version       = Batali::VERSION

  gem.add_dependency "ridley", ">= 2.5.1"
  gem.add_dependency "pmap", "~> 1.0.1"
  gem.add_dependency "fog", "~> 1.21.0"
end
