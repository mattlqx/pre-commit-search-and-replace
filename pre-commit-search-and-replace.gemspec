Gem::Specification.new do |s|
    s.name        = 'pre-commit-search-and-replace'
    s.version     = '1.1.2'
    s.licenses    = ['MIT']
    s.summary     = "A pre-commit hook that searches for strings and replaces them."
    s.description = "With this hook, you may define patterns in a config file to search commits for and replace them as desired."
    s.authors     = ["Matt Kulka"]
    s.email       = 'matt@lqx.net'
    s.files       = ["bin/search-and-replace", "lib/search-and-replace.rb"]
    s.add_runtime_dependency 'rainbow', '~> 3.1'
    s.executables = ["search-and-replace"]
    s.homepage    = 'https://github.com/mattlqx/pre-commit-search-and-replace'
    s.metadata    = { "source_code_uri" => "https://github.com/mattlqx/pre-commit-search-and-replace" }
  end