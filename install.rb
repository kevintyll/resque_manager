require 'fileutils'

public_dir = File.join(File.dirname(__FILE__),'/../../../public')
asset_dir = File.join(File.dirname(__FILE__), 'assets')

['images','stylesheets','javascripts'].each do |asset_type|
  copy_from = File.join(asset_dir, asset_type)
  copy_to = File.join(public_dir,asset_type,'resque')

  FileUtils.mkdir(copy_to) unless File.exists? copy_to
  Dir.entries(copy_from).each do |f|
    new_file = File.join(copy_to,f)
    from_file = File.join(copy_from,f)
    FileUtils.cp(from_file, new_file) unless File.exist?(new_file) || File.directory?(from_file)
  end
end
puts IO.read(File.join(File.dirname(__FILE__), 'README'))