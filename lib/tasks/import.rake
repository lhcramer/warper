#called using arguments
#example: RAILS_ENV=development rake warper:import_images['/home/tim/tmp/helsinki',2,,,'helsinki','helsinki2']

namespace :warper do
  desc "Import images from a directory to map"
  task :import_images, [:directory, :user, :layer, :layer_name, :title, :description, :scale]  => :environment  do |t, args|
  
    puts "\nImporting images from directory into new map objects....\n"
    puts "Args were: #{args}"
    usage = "::::::USAGE::::::\nrake warper:import_images['path/to/dir/with/images REQUIRED',user id (int) REQUIRED, layer id (int) OPTIONAL [-99 for new layer, leave blank for no layer],
'title for new layer' OPTIONAL, 'default title suffix for maps' OPTIONAL, 'default description for maps' OPTIONAL,
'default scale for maps' OPTIONAL ] \n\nEXAMPLE  rake warper:import_images['/home/tim/maps/yorkshire/',23,-99,'Best Yorkshire maps','Yorkshire'] "
    #check to make sure the args are filled in properly
    
    if args.directory.empty? || args.user.empty?
      puts "No directory or user passed in as args"
      puts usage
      break
    end

    unless User.exists?(args.user.to_i)
      puts "No user found with id " + args.user.to_s
      puts usage
      break
    else
      user = User.find_by_id(args.user.to_i)
      puts "Maps will be uploaded by user "+user.login.to_s
    end

    if Layer.exists?(args.layer.to_i)
      layer = Layer.find(args.layer.to_i)
      puts "Maps will be associated with Layer " + layer.id.to_s
    elsif !args.layer.empty? && args.layer.to_i == -99
      unless args.layer_name.empty?
        puts "Creating new Layer with title: " + args.layer_name
      else
        puts "Creating new Layer..."
      end
      layer = Layer.new(:name => args.layer_name)
      layer.user = user
      layer.save
    elsif !args.layer.empty? 
      puts "No layer found with id " + args.layer.to_s
      puts usage
      break
    else
      layer = nil
    end

    #image extensions to work with
    include_exts = [".tif", ".gif", ".png", ".jpg", ".jpeg", ".tif.png", ".tiff"]

    basedir = args.directory

    #fixed tags for fields for all models.
    default_title_suffix = " " + args.title.to_s || ""
    default_description = args.description.to_s || nil
    default_scale = args.scale.to_s || nil

    #////////////////#
    puts "Directory containing images: " + basedir
    puts "Found " + (Dir.entries(basedir).size - 2).to_s + " files in this directory. Will try to import images."
    puts
    puts "WARNING: This may slow down this computer, especially if you've a lot of images!"
    print "Are you sure you want to continue ? [y/N] "
    break unless STDIN.gets.match(/^y$/i)
    puts
   
    puts "Importing "
    count = 0
    puts ""

    Dir.foreach(basedir) do | ourfilename |
      print '.'
      print ourfilename
      unless Map.exists?(:upload_file_name => ourfilename)
        print '+'
        map = Map.new(:title => ourfilename + default_title_suffix, :description => default_description, :scale => default_scale)
        ourfile = File.join(basedir , ourfilename)
        map.owner = user
        map.users << user
        if layer
          map.layers << layer
        end
        
        File.open(ourfile) { |photo_file| map.upload = photo_file }
        
        count += 1 if map.save
        if map.errors.get(:filename)
          #should be caught, but just in case
          puts  ""
          puts "Map has same name, wasn't imported: " + ourfilename.to_s
         
        end
      end if include_exts.include?(File.extname(ourfilename).downcase.to_s)
    end
    puts ""
    puts "Finished Importing. Number imported: "+ count.to_s
   
  end
end
