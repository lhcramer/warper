class MapsController < ApplicationController

  layout 'mapdetail', :only => [:show, :preview, :warp, :clip, :align, :activity, :warped, :export, :metadata]
  
  before_filter :store_location, :only => [:warp, :align, :clip, :export, :edit ]
   
  before_filter :check_administrator_role, :only => [:publish, :edit]
 
  before_filter :find_map_if_available,
    :except => [:show, :index, :wms, :tile, :mapserver_wms, :warp_aligned, :status, :new, :create, :update, :destroy, :edit, :tag, :geosearch]
  
  rescue_from ActiveRecord::RecordNotFound, :with => :bad_record

  # Speed up WMS serving. How do we invalidate if file is re-uploaded?
  # would need to append a version into the param
  caches_action :wms, cache_path: -> { params }



  helper :sort
  include SortHelper
  
  def new
    @map = Map.new
    @html_title = "Upload a new map to "
    @max_size = Map.max_attachment_size

    # We could technically set status here to :loading, but no other process
    # would see it yet, so no reason to.

    if Map.max_dimension
      @upload_file_message  = " It may resize the image if it's too large (#{Map.max_dimension}x#{Map.max_dimension}) "
    else
      @upload_file_message = ""
    end
  end

  def create
    @map = Map.new(map_params)
    
    if user_signed_in?
      @map.users << current_user
    end

    # File has been uploaded, go ahead and set status now.
    @map.status = :available

    respond_to do |format|
      if @map.save
        flash[:notice] = 'Map was successfully created.'
        format.html { redirect_to(@map) }
      else
        format.html { render :action => "new", :layout =>'application' }
      end
    end
  end

  # TODO: Should only allow edits if user that owns map, or administrator
  def edit
    @map = Map.find(params[:id])
  end

  def update
    @map = Map.find(params[:id])
    respond_to do |format|
      if @map.update(map_params)
        format.html { redirect_to @map, notice: 'Map was successfully updated.' }
      else
        format.html { render action: 'edit' }
      end
    end
  end

  def destroy
    @map = Map.find(params[:id])
    @map.destroy
    respond_to do |format|
      format.html { redirect_to maps_url }
    end
  end
 
  
  ###############
  #
  # Collection actions 
  #
  ###############
  def index
    sort_init('updated_at', {:default_order => "desc"})
    
    sort_update
    @show_warped = params[:show_warped]
    request.query_string.length > 0 ?  qstring = "?" + request.query_string : qstring = ""
        
    @query = params[:query]
        
    # What we are searching.
    where_col  = "(title || ' ' || description)"
    
    #we'll use POSIX regular expression for searches    ~*'( |^)robinson([^A-z]|$)' and to strip out brakets etc  ~*'(:punct:|^|)plate 6([^A-z]|$)';
    if @query && @query.strip.length > 0
      conditions = ["#{where_col}  ~* ?", '(:punct:|^|)'+@query+'([^A-z]|$)']
    else
      conditions = nil
    end
                    
    if params[:sort_order] && params[:sort_order] == "desc"
      sort_nulls = " NULLS LAST"
    else
      sort_nulls = " NULLS FIRST"
    end
    @per_page = params[:per_page] || 50
    paginate_params = {
      :page => params[:page],
      :per_page => @per_page
    }
    order_options = sort_clause + sort_nulls
    where_options = conditions
    #order('name').where('name LIKE ?', "%#{search}%").paginate(page: page, per_page: 10)
    
    if @show_warped == "1"
      @maps = Map.warped.where(where_options).order(order_options).paginate(paginate_params)
    else
      @maps = Map.where(where_options).order(order_options).paginate(paginate_params)
    end
    
    @html_title = "Browse Maps"
    if request.xhr?
      render :action => 'index.rjs'
    else
      respond_to do |format|
        format.html{ render :layout =>'application' }  # index.html.erb
        format.xml  { render :xml => @maps.to_xml(:root => "maps", :except => [:content_type, :filename, :parent_id,  :map, :thumbnail, :rough_centroid]) {|xml|
            xml.tag!'stat', "ok"
            xml.tag!'total-entries', @maps.total_entries
            xml.tag!'per-page', @maps.per_page
            xml.tag!'current-page',@maps.current_page} }
        
        format.json { render :json => {:stat => "ok",
            :current_page => @maps.current_page,
            :per_page => @maps.per_page,
            :total_entries => @maps.total_entries,
            :total_pages => @maps.total_pages,
            :items => @maps.to_a}.to_json(:except => [:content_type, :parent_id, :map, :rough_centroid]) , :callback => params[:callback]
        }
      end
    end
    
  end
  
  
    
  def geosearch
    require 'geoplanet'
    sort_init 'updated_at'
    sort_update

    extents = [-74.1710,40.5883,-73.4809,40.8485] #NYC

    #TODO change to straight javascript call.
    if params[:place] && !params[:place].blank?
      place_query = params[:place]
      GeoPlanet.appid = APP_CONFIG['yahoo_app_id']
      
      geoplanet_result = GeoPlanet::Place.search(place_query, :count => 2)
      
      if geoplanet_result[0]
        g_bbox =  geoplanet_result[0].bounding_box.map!{|x| x.reverse}
        extents = g_bbox[1] + g_bbox[0]
        render :json => extents.to_json
        return
      else
        render :json => extents.to_json
        return
      end
    end

    if params[:bbox] && params[:bbox].split(',').size == 4
      begin
        extents = params[:bbox].split(',').collect {|i| Float(i)}
      rescue ArgumentError
        logger.debug "arg error with bbox, setting extent to defaults"
      end
    end
    @bbox = extents.join(',')

    if extents
      bbox_poly_ary = [
        [ extents[0], extents[1] ],
        [ extents[2], extents[1] ],
        [ extents[2], extents[3] ],
        [ extents[0], extents[3] ],
        [ extents[0], extents[1] ]
      ]
      
      map_srid = 0
      map_srid = Map.warped.first.bbox_geom.srid if Map.warped.first && Map.warped.first.bbox_geom
      if map_srid == 0
        bbox_polygon = GeoRuby::SimpleFeatures::Polygon.from_coordinates([bbox_poly_ary]).as_wkt
      else
        bbox_polygon = GeoRuby::SimpleFeatures::Polygon.from_coordinates([bbox_poly_ary]).as_ewkt
      end
      if params[:operation] == "within"
        conditions = ["ST_Within(bbox_geom, ST_GeomFromText('#{bbox_polygon}'))"]
      else
        conditions = ["ST_Intersects(bbox_geom, ST_GeomFromText('#{bbox_polygon}'))"]
      end

    else
      conditions = nil
    end


    if params[:sort_order] && params[:sort_order] == "desc"
      sort_nulls = " NULLS LAST"
    else
      sort_nulls = " NULLS FIRST"
    end


      @operation = params[:operation]

    if @operation == "intersect"
      sort_geo = "ABS(ST_Area(bbox_geom) - ST_Area(ST_GeomFromText('#{bbox_polygon}'))) ASC,  "
    else
      sort_geo ="ST_Area(bbox_geom) DESC ,"
    end
    
    status_conditions = {:status => [Map.status(:warped), Map.status(:published), Map.status(:publishing)]}
    
    paginate_params = {
      :page => params[:page],
      :per_page => 20
    }
    order_params = sort_geo + sort_clause + sort_nulls
    @maps = Map.select("bbox, title, description, updated_at, id, status").warped.where(conditions).where(status_conditions).order(order_params).paginate(paginate_params)
    @jsonmaps = @maps.to_json
    respond_to do |format|
      format.html{ render :layout =>'application' }
      
      format.json { render :json => {:stat => "ok",
        :current_page => @maps.current_page,
        :per_page => @maps.per_page,
        :total_entries => @maps.total_entries,
        :total_pages => @maps.total_pages,
        :items => @maps.to_a}.to_json , :callback => params[:callback]}
    end
  end
  
  
  ###############
  #
  # Tab actions 
  #
  ###############
  
  def show
    @current_tab = "show"
    @selected_tab = 0
    @disabled_tabs =[]
    @map = Map.find(params[:id])
    @html_title = "Viewing Map #{@map.id}"

    if @map.status.nil? || @map.status == :unloaded
      @mapstatus = "unloaded"
    else
      @mapstatus = @map.status.to_s
    end

    #
    # Not Logged in users
    #
    if !user_signed_in?
      @disabled_tabs = ["warp", "clip", "align", "activity"]
      
      if @map.status.nil? or @map.status == :unloaded or @map.status == :loading
        @disabled_tabs += ["warped"]
      end
      
      flash.now[:notice] = "You may need to %s to start editing the map"
      flash.now[:notice_item] = ["log in", :login]
      session[:user_return_to] = request.url
      
      if request.xhr?
        @xhr_flag = "xhr"
        render :action => "preview", :layout => "tab_container"
      else
        respond_to do |format|
          format.html {render :action => "preview"}
          format.kml {render :action => "show_kml", :layout => false}
          format.rss {render :action=> 'show'}
          format.json {render :json =>{:stat => "ok", :items => @map}.to_json(:except => [:content_type, :size, :filename, :parent_id,  :map, :thumbnail, :rough_centroid]), :callback => params[:callback] }
        end
      end
      
      return #stop doing anything more
    end

    #End doing stuff for not logged in users.


    #
    # Logged in users
    #
    
    unless user_signed_in? and current_user.has_role?("administrator")
      if @map.status == :publishing or @map.status == :published
        @disabled_tabs += ["warp", "clip", "align"]  #dont show any others unless you're an editor
      end
    end

    @title = "Viewing original map. "

    if !@map.warped_or_published?
      @title += "This map has not been warped yet."
    end
     
    if request.xhr?
      choose_layout_if_ajax
    else
      respond_to do |format|
        format.html
        format.kml {render :action => "show_kml", :layout => false}
        format.json {render :json =>{:stat => "ok", :items => @map}.to_json(:except => [:content_type, :size, :bbox_geom, :uuid, :filename, :parent_id,  :map, :thumbnail, :rough_centroid]), :callback => params[:callback] }
      end
    end    
  end
  
  def export
    @current_tab = "export"
    @selected_tab = 5
    @html_title = "Export Map" + @map.id.to_s
    
    choose_layout_if_ajax
    
    respond_to do | format |
      format.html {}
      format.tif {  send_file @map.warped_filename }
      format.png  { send_file @map.warped_png }
      format.aux_xml { send_file @map.warped_png_aux_xml }
    end
  end
  
  # Download the original file that was uploaded
  # This can be in any number of formats
  def download
    @map = Map.find(params[:id])
    send_file @map.upload.path
  end


  def clip
    #TODO delete current_tab
    @current_tab = "clip"
    @selected_tab = 3
    @html_title = "Cropping Map "+ @map.id.to_s
    @gml_exists = "false"
    if File.exists?(@map.masking_file_gml+".ol")
      @gml_exists = "true"
    end
    if APP_CONFIG['mask_dir'].blank?
      @gml_url = "/warper/mapimages/#{@map.id}.gml.ol?#{Time.now.to_i}"
    else
      @gml_url = "#{request.protocol}#{request.host_with_port}/shared/masks/#{@map.id}.gml.ol?#{Time.now.to_i}"
    end
    choose_layout_if_ajax
  end
  
  
  def warped
    @current_tab = "warped"
    @selected_tab = 5
    @html_title = "Viewing Rectfied Map "+ @map.id.to_s
    if (@map.warped_or_published? || @map.status == :publishing) && @map.gcps.hard.size > 2 
      @other_layers = Array.new
      @map.layers.visible.each do |layer|
        @other_layers.push(layer.id)
      end

    else
      flash.now[:notice] = "Whoops, the map needs to be rectified before you can view it"
    end
    choose_layout_if_ajax
  end
  
  def align
    @html_title = "Align Maps "
    @current_tab = "align"
    @selected_tab = 3

    choose_layout_if_ajax
  end

  # Return the thumbnail of a given map
  def thumb
    @map = Map.find(params[:id])

    send_file(@map.upload.path(:thumb), disposition: :inline)
  end

  def warp
    @current_tab = "warp"
    @selected_tab = 2
    @html_title = "Rectifying Map "+ @map.id.to_s
    @bestguess_places = @map.find_bestguess_places  if @map.gcps.hard.empty?
    @other_layers = Array.new
    @map.layers.visible.each do |layer| 
      @other_layers.push(layer.id)
    end

    @gcps = @map.gcps_with_error 

    choose_layout_if_ajax 
  end
  
  def metadata
    choose_layout_if_ajax
  end
  
  
  def trace
    redirect_to map_path unless @map.published?
    @overlay = @map
  end
  
  def id
    redirect_to map_path unless @map.published?
    @overlay = @map
    render "id", :layout => false
  end
  
  # called by id JS oauth
  def idland
    render "idland", :layout => false
  end
  
  ###############
  #
  # Other / API actions 
  #
  ###############  

  #pass in soft true to get soft gcps
  def gcps
    @map = Map.find(params[:id])
    gcps = @map.gcps_with_error(params[:soft])
    respond_to do |format|
      format.html { render :json => {:stat => "ok", :items => gcps.to_a}.to_json(:methods => :error), :callback => params[:callback]}
      format.json { render :json => {:stat => "ok", :items => gcps.to_a}.to_json(:methods => :error), :callback => params[:callback]}
      format.xml { render :xml => gcps.to_xml(:methods => :error)}
    end
  end
  
  
  
  def get_rough_centroid
    map = Map.find(params[:id])
    respond_to do |format|
      format.json {render :json =>{:stat => "ok", :items => map}.to_json(:except => [:content_type, :size, :bbox_geom, :uuid, :filename, :parent_id,  :map, :thumbnail]), :callback => params[:callback]  }
    end
  end
  
  def set_rough_centroid
    map = Map.find(params[:id])
    lon = params[:lon]
    lat = params[:lat]
    zoom = params[:zoom]
    respond_to do |format|
      if map.update_attributes(:rough_lon  => lon, :rough_lat => lat, :rough_zoom => zoom ) && lat && lon
        map.save_rough_centroid(lon, lat)
        format.json {render :json =>{:stat => "ok", :items => map}.to_json(:except => [:content_type, :size, :bbox_geom, :uuid, :filename, :parent_id,  :map, :thumbnail, :rough_centroid]), :callback => params[:callback]
        }
      else
        format.json { render :json => {:stat => "fail", :message => "Rough centroid not set", :items => [], :errors => map.errors.to_a}.to_json, :callback => params[:callback]}
      end
    end
  end

  def get_rough_state
    map = Map.find(params[:id])
    respond_to do |format|
      if map.rough_state
        format.json { render :json => {:stat => "ok", :items => ["id" => map.id, "rough_state" => map.rough_state]}.to_json, :callback => params[:callback]}
      else
        format.json { render :json => {:stat => "fail", :message => "Rough state is null", :items => map.rough_state}.to_json, :callback => params[:callback]}
      end
    end
  end

  def set_rough_state
    map = Map.find(params[:id])
    respond_to do |format|
      if map.update_attributes(:rough_state => params[:rough_state]) && Map::ROUGH_STATE.include?(params[:rough_state].to_sym)
        format.json { render :json => {:stat => "ok", :items => ["id" => map.id, "rough_state" => map.rough_state]}.to_json, :callback => params[:callback] }
      else
        format.json { render :json => {:stat => "fail", :message =>"Could not update state", :errors => map.errors.to_a, :items => []}.to_json , :callback => params[:callback]}
      end
    end
  end

  # for ajax update / progress bar on map load status
  def status
    map = Map.find(params[:id])
    if map.status.nil?
      sta = "loading"
    else
      sta = map.status.to_s
    end
    render :text =>  sta
  end
  
  #should check for admin only
  def publish
    # if @map.status == :publishing
    #   flash[:notice] = "Map currently publishing. Please try again later."
    #   return redirect_to @map
    # end
    if params[:to] == "publish" && @map.status == :warped
      @map.publish
      flash[:notice] = "Map publishing. Please wait as the map will be published and tiles transfered via tilestache. Status: " + @map.status.to_s
    elsif params[:to] == "unpublish" && (@map.status == :published || @map.status == :publishing)
      @map.unpublish
      flash[:notice] = "Map unpublished. Status: " + @map.status.to_s
    end

    redirect_to @map
  end

  def save_mask
    message = @map.save_mask(params[:output])
    respond_to do | format |
      format.html {render :text => message}
      format.js { render :text => message} if request.xhr?
      format.json {render :json => {:stat =>"ok", :message => message}.to_json , :callback => params[:callback]}
    end
  end

  def delete_mask
    message = @map.delete_mask
    respond_to do | format |
      format.html { render :text => message}
      format.js { render :text => message} #if request.xhr?
      format.json {render :json => {:stat =>"ok", :message => message}.to_json , :callback => params[:callback]}
    end
  end

  def mask_map
    respond_to do | format |
      if File.exists?(@map.masking_file_gml)
        message = @map.mask!
        format.html { render :text => message }
        format.js { render :text => message} #if request.xhr?
        format.json { render :json => {:stat =>"ok", :message => message}.to_json , :callback => params[:callback]}
      else
        message = "Mask file not found"
        format.html { render :text => message  }
        format.js { render :text => message} #if request.xhr?
        format.json { render :json => {:stat =>"fail", :message => message}.to_json , :callback => params[:callback]}
      end
    end
  end
  
  def save_mask_and_warp
    logger.debug "save mask and warp"
    
    if @map.status == :publishing or @map.status == :published
      stat = "fail"
      msg = "Mask not applied. Map is published so is unable to mask."
    elsif @map.status == :warping
      stat = "fail"
      msg = "Mask not saved as the map is currently being rectified somewhere else, please try again later."
    else
      @map.save_mask(params[:output])
      @map.mask!
      stat = "ok"
      if @map.gcps.hard.size.nil? || @map.gcps.hard.size < 3
        msg = "Map masked, but it needs more control points to rectify. Click the Rectify tab to add some."
        stat = "fail"
      else
        params[:use_mask] = "true"
        rectify_main
        msg = "Map masked and rectified."
      end
    
    end

    respond_to do |format|
      format.json {render :json => {:stat => stat, :message => msg}.to_json , :callback => params[:callback]}
      format.js { render :text => msg } if request.xhr?
    end
  end



  #just works with NSEW directions at the moment.
  def warp_aligned
    
    align = params[:align]
    append = params[:append]
    destmap = Map.find(params[:destmap])

    if destmap.status.nil? or destmap.status == :unloaded or destmap.status == :loading
      flash.now[:notice] = "Sorry the destination map is not available to be aligned."
      redirect_to :action => "show", :id=> params[:destmap]
    elsif align != "other"

      if params[:align_type]  == "original"
        destmap.align_with_original(params[:srcmap], align, append )
      else
        destmap.align_with_warped(params[:srcmap], align, append )
      end
      flash.now[:notice] = "Map aligned. You can now rectify it!"
      redirect_to :action => "show", :id => destmap.id, :anchor => "Rectify_tab"
    else
      flash.now[:notice] = "Sorry, only horizontal and vertical alignment are available at the moment."
      redirect_to :action => "align", :id=> params[:srcmap], :anchor => "Align_tab"
    end
  end



  def rectify
    rectify_main

    respond_to do |format|
      unless @too_few || @fail
        format.js 
        format.html { render :text => @notice_text }
        format.json { render :json=> {:stat => "ok", :message => @notice_text}.to_json, :callback => params[:callback] }
      else
        format.js
        format.html { render :text => @notice_text }
        format.json { render :json=> {:stat => "fail", :message => @notice_text}.to_json , :callback => params[:callback]}
      end
    end
     
  end
  

  # TODO: Look into action caching or rack::cache for this
  # or possibly roll our own cache. Need to think about invalidation
  # options. We should be able to monitor @map updated_at and status (along with query params?)
  # as it could greatly speed up serving
  #
  # Should these ever be private? We can't cache if we have to enforce permissions...
  def wms
    @map = Map.find(params[:id])

    #status is additional query param to show the unwarped wms
    wms_status = params["STATUS"].to_s.downcase || "unwarped"
    ows = Mapscript::OWSRequest.new
    
    # TODO: Should rework this with more modern params handling..
    ok_params = Hash.new
    # params.each {|k,v| k.upcase! } frozen string error
    params.each {|k,v| ok_params[k.upcase] = v }
    [:request, :version, :transparency, :service, :srs, :width, :height, :bbox, :format, :srs].each do |key|
      ows.setParameter(key.to_s, ok_params[key.to_s.upcase]) unless ok_params[key.to_s.upcase].nil?
    end
    
    ows.setParameter("VeRsIoN","1.1.1")
    ows.setParameter("STYLES", "")
    ows.setParameter("LAYERS", "image")
    ows.setParameter("COVERAGE", "image")

    result_data, content_type = Wms.dispatch(ows, wms_status, @map)

    send_data result_data, :type => content_type, :disposition => "inline"
  end
  
  # for tile map - basically proxies requests to wms in a simpler
  # url format...
  #
  # This is an "export" option - which specifies PNG. We probably
  # want to change this to jpeg in the future as well.
  def tile
    x = params[:x].to_i
    y = params[:y].to_i
    z = params[:z].to_i
    #for Google/OSM tile scheme we need to alter the y:
    y = ((2**z)-y-1)
    #calculate the bbox
    params[:bbox] = get_tile_bbox(x,y,z)
    #build up the other params
    params[:status] = "warped"
    params[:format] = "image/png"
    params[:service] = "WMS"
    params[:version] = "1.1.1"
    params[:request] = "GetMap"
    params[:srs] = "EPSG:900913"
    params[:width] = "256"
    params[:height] = "256"
    #call the wms thing
    wms
    
  end
  
  
  private


  def rectify_main
    resample_param = params[:resample_options] || @map.resample_options
    transform_param = params[:transform_options] || @map.transform_options
    masking_option = params[:mask]
    resample_option = ""
    transform_option = ""
    case transform_param
    when "auto"
      transform_option = ""
    when "p1"
      transform_option = " -order 1 "
    when "p2"
      transform_option = " -order 2 "
    when "p3"
      transform_option = " -order 3 "
    when "tps"
      transform_option = " -tps "
    else
      transform_option = ""
    end

    case resample_param
    when "near"
      resample_option = " -rn "
    when "bilinear"
      resample_option = " -rb "
    when "cubic"
      resample_option = " -rc "
    when "cubicspline"
      resample_option = " -rcs "
    when "lanczos" #its very very slow
      resample_option = " -rn "
    else
      resample_option = " -rn"
    end

    use_mask = params[:use_mask]
    @too_few = false
    if @map.gcps.hard.size.nil? || @map.gcps.hard.size < 3
      @too_few = true
      @notice_text = "Sorry, the map needs at least three control points to be able to rectify it"
      @output = @notice_text
    elsif @map.status == :warping 
      @fail = true
      @notice_text = "Sorry, the map is currently being rectified somewhere else, please try again later."
      @output = @notice_text
    elsif @map.status == :publishing or @map.status == :published
      @fail = true
      @notice_text = "Sorry, this map is published, and cannot be rectified."
      @output = @notice_text
    else
      # save new rectify params in db
      @map[:resample_options] = resample_param
      @map[:transform_options] = transform_param
      @map.save

      if user_signed_in?
        um  = current_user.my_maps.new(:map => @map)
        um.save

      end

      @output = @map.warp! transform_option, resample_option, use_mask #,masking_option
      @notice_text = "Map rectified."
    end
  end
  
  
  # tile utility methods. calculates the bounding box for a given TMS tile.
  # Based on http://www.maptiler.org/google-maps-coordinates-tile-bounds-projection/
  # GDAL2Tiles, Google Summer of Code 2007 & 2008
  # by  Klokan Petr Pridal
  def get_tile_bbox(x,y,z)
    min_x, min_y = get_merc_coords(x * 256, y * 256, z)
    max_x, max_y = get_merc_coords( (x + 1) * 256, (y + 1) * 256, z )
    return "#{min_x},#{min_y},#{max_x},#{max_y}"
  end

  def get_merc_coords(x,y,z)
    resolution = (2 * Math::PI * 6378137 / 256) / (2 ** z)
    merc_x = (x * resolution -2 * Math::PI  * 6378137 / 2.0)
    merc_y = (y * resolution - 2 * Math::PI  * 6378137 / 2.0)
    return merc_x, merc_y
  end
  
  #only allow deleting by a user if the user owns it
  def check_if_map_can_be_deleted
    if user_signed_in? and (current_user.own_this_map?(params[:id])  or current_user.has_role?("editor"))
      @map = Map.find(params[:id])
    else
      flash[:notice] = "Sorry, you cannot delete other people's maps!"
      redirect_to map_path
    end
  end

  def bad_record
    #logger.error("not found #{params[:id]}")
    respond_to do | format |
      format.html do
        flash[:notice] = "Map not found"
        redirect_to :action => :index
      end
      format.json {render :json => {:stat => "not found", :items =>[]}.to_json, :status => 404}
    end
  end

  #only allow editing by a user if the user owns it, or if and editor tries to edit it
#  def check_if_map_is_editable
#    if user_signed_in? and (current_user.own_this_map?(params[:id])  or current_user.has_role?("editor"))
#      @map = Map.find(params[:id])
#    elsif Map.find(params[:id]).owner.nil?
#      @map = Map.find(params[:id])
#    else
#      flash[:notice] = "Sorry, you cannot edit other people's maps"
#      redirect_to map_path
#    end
#  end

  # TODO: This should support xhr requests properly.
  # right now it just shows a blank page as the tab doesn't
  # understand what to do with the redirect...
  def find_map_if_available

    @map = Map.find(params[:id])

    Rails.logger.debug "Map status is: #{@map.status}"

    if @map.status.nil? or @map.status == :unloaded or @map.status == :loading 
      redirect_to map_path
    end
  end

  def map_params
    params.require(:map).permit(:title, :description, :upload) 
  end
  
  def choose_layout_if_ajax
    if request.xhr?
      @xhr_flag = "xhr"
      render :layout => "tab_container"
    end
  end
  

   
  def store_location
    case request.parameters[:action]
    when "warp"
      anchor = "Rectify_tab"
    when "clip"
      anchor = "Crop_tab"
    when "align"
      anchor = "Align_tab"
    when "export"
      anchor = "Export_tab"
    else
      anchor = ""
    end

    return if anchor.blank?

    if request.parameters[:action] &&  request.parameters[:id]
      session[:user_return_to] = map_path(:id => request.parameters[:id], :anchor => anchor)
    else
      session[:user_return_to] = request.url
    end
    
  end
  
  
end
