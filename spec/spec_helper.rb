require 'tmpdir'
require 'fileutils'

# Some dependencies may not be installed as Ruby Gems but as local sources.
# Add them and the postrunner dir to the LOAD_PATH.
%w( cartracker perobs ).each do |lib_dir|
  $:.unshift(File.join(File.dirname(__FILE__), '..', '..', lib_dir, 'lib'))
end

def tmp_dir_name(caller_file)
  begin
    dir_name = File.join(Dir.tmpdir,
                         "#{File.basename(caller_file)}.#{rand(2**32)}")
  end while File.exists?(dir_name)

  dir_name
end

def create_working_dirs
  @work_dir = tmp_dir_name(__FILE__)
  Dir.mkdir(@work_dir)
end

def cleanup
  FileUtils.rm_rf(@work_dir)
end

def create_store
  @store = PEROBS::Store.new(File.join(@work_dir, 'db'))
end

