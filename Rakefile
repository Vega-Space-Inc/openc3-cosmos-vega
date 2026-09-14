# Copyright 2026 Vega Space, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from Vega Space, Inc.

PLUGIN_NAME = Dir['*.gemspec'][0].split('.')[0..-2].join('.')

task :require_version do
  unless ENV['VERSION']
    puts "VERSION is required: rake build VERSION=X.Y.Z"
    exit 1
  end
end

task :build => [:require_version] do
  _, platform, *_ = RUBY_PLATFORM.split("-")
  if platform == 'mswin32' or platform == 'mingw32'
    puts "Warning: Building gem on Windows will lose file permissions"
  end
  # Build the widget and gem using sh built into Rake:
  # https://rubydoc.info/gems/rake/FileUtils#sh-instance_method
  sh('pnpm', 'run', 'build')
  sh('gem', 'build', PLUGIN_NAME)
  sh('openc3cli validate *.gem') do |ok, status|
    if !ok && status.exitstatus == 127 # command not found
      puts "Install the openc3 gem to validate! (gem install openc3)"
    end
  end
end
