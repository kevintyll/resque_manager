require 'fileutils'

public_dir = File.join(File.dirname(__FILE__),'/../../../public')
asset_dir = File.join(File.dirname(__FILE__), 'assets')
['images','stylesheets','javascripts'].each do |asset_type|
  current_dir = File.join(asset_dir, asset_type)
  Dir.entries(current_dir).each do |f|
    path = File.join(public_dir,asset_type,f)
    FileUtils.rm(path) if File.exist?(path) && File.file?(path)
  end
end