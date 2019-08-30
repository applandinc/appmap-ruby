require 'bundler/gem_tasks'
require 'rake/testtask'
require 'rdoc/task'

begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec).tap do |task|
    task.exclude_pattern = 'spec/fixtures/**/*_spec.rb'
  end
rescue LoadError
  warn "Rake task 'spec' could not be loaded"
end

Rake::RDocTask.new do |rd|
  rd.main = 'README.rdoc'
  rd.rdoc_files.include(%w[README.rdoc lib/**/*.rb exe/**/*])
  rd.title = 'AppMap'
end

Rake::TestTask.new(:minitest) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList['test/**/*_test.rb']
end

desc 'Build the Docker base image used by the test fixtures'
task build_docker_base: :build do
  require 'appmap/version'
  version = AppMap::VERSION
  system "docker build --build-arg GEM_VERSION=#{version} -t appmap-ruby_with_appmap:2.6 -f Dockerfile.ruby_with_appmap ." \
    or raise 'Docker build failed'
end

desc 'Build the Docker images used by the test fixtures'
task build_docker_tests: %i[build build_docker_base] do
  %w[rack_users_app rails_users_app].each do |dir|
    Dir.chdir "spec/fixtures/#{dir}" do
      system 'docker-compose build' or raise 'docker-compose build failed'
    end
  end
end

desc 'Build the project, Docker base images, and test images'
task build_docker: %i[build build_docker_base build_docker_tests]

task test: %i[build build_docker minitest spec]

task default: :test
