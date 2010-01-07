require 'fileutils'

public_dir = File.join(File.dirname(__FILE__),'/../../../public')
['images','stylesheets','javascripts'].each do |asset_type|

  path = File.join(public_dir,asset_type,'resque')
  FileUtils.rm_r(path) if File.exist?(path)
end