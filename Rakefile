require "rake/testtask"
require "freno/client/version"

# gem install pkg/*.gem
# gem uninstall freno-client freno-throttler
desc "Build gem into the pkg directory"
task :build do
  FileUtils.rm_rf("pkg")
  Dir["*.gemspec"].each do |gemspec|
    system "gem build #{gemspec}"
  end
  FileUtils.mkdir_p("pkg")
  FileUtils.mv(Dir["*.gem"], "pkg")
end

desc "Tags version, pushes to remote, and pushes gem"
task release: :build do
  sh "git", "tag", "v#{Freno::Client::VERSION}"
  sh "git push origin master"
  sh "git push origin v#{Freno::Client::VERSION}"
  sh "ls pkg/*.gem | xargs -n 1 gem push"
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

task default: :test
