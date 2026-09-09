# encoding: ascii-8bit

# Create the overall gemspec
Gem::Specification.new do |s|
  s.name = 'openc3-cosmos-vega'
  s.summary = 'Vega Space satellite interference data as COSMOS telemetry'
  s.description = <<-EOF
    Polls the Vega Space REST API (vega.space) for account, ground station,
    and tracked satellite data and surfaces it as COSMOS telemetry.
  EOF
  s.licenses = 'MIT'
  s.authors = ['Vega']
  s.email = ['tom@vega.space']
  s.homepage = 'https://vega.space'
  s.platform = Gem::Platform::RUBY
  s.required_ruby_version = '>= 3.0'

  if ENV['VERSION']
    s.version = ENV['VERSION'].dup
  else
    time = Time.now.strftime("%Y%m%d%H%M%S")
    s.version = '0.0.0' + ".#{time}"
  end
  s.files = Dir.glob("{targets,lib,public,tools,microservices}/**/*") + %w(Rakefile README.md LICENSE.md plugin.txt)

  s.metadata = {
    # These fields are used when you submit your plugin to the OpenC3 Store at store.openc3.com
    # See this help page for more detail: https://store.openc3.com/help/guidelines
    "source_code_uri" => "https://github.com/your-github/plugin-repo",
    "openc3_store_title" => "Vega Space",
    "openc3_store_description" => "Pulls satellite interference/coverage data from the Vega Space API into COSMOS telemetry.",
    "openc3_store_keywords" => "vega, satellite, interference, spectrum, rf, coverage",
    "openc3_store_image" => "public/store_img.png",
    "openc3_cosmos_minimum_version" => "6.0.0", # OPTIONAL
    "openc3_store_access_type" => "public" # OPTIONAL
  }
end
