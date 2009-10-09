require 'lib/panda'
require 'run_later'

module Panda
  class InvalidRequest < StandardError; end
  class RecordNotFound < StandardError; end
  class CannotDelete < StandardError; end
  
  class Server < Sinatra::Base
    configure(:test) do
      # set :raise_errors, false
    end
    # TODO: Auth similar to Amazon where we hash all the form params plus the api key and send a signature
    
    # mime :json, "application/json"
        
    def display_response(object, ext)
      if request.env['panda.iframe']
        content_type :html
        return "<textarea>#{object.to_json}</textarea>"
      else
        case ext.to_sym
        when :json
          content_type :json
          return object.to_json
        # when :xml
        #   content_type :xml
        #   r = object.to_xml
        else
          raise InvalidRequest, "Currently only .json is supported as a format"
        end
      end
    end
    
    # Errors
    
    def display_error(s)
      status s
      # TODO: support xml in returned error messages
      r = {:error => request.env['sinatra.error'].class.to_s.split('::').last, :message => request.env['sinatra.error'].message}
      display_response(r, :json)
    end
    
    error do
      display_error 500
    end
    
    error ActiveRecord::RecordNotFound do
      display_error 404
    end
    
    error InvalidRequest do
      display_error 400
    end
    
    error Video::VideoError do
      display_error 422
    end
    
    error CannotDelete do
      display_error 422
    end
    
    # Params
    
    def required_params(params, *params_list)
      params_list.each do |p|
        raise(InvalidRequest, "All required parameters were not supplied") unless params.has_key?(p.to_s)
      end
    end
    
    def select_params(params, *params_list)
      only_selected_params = {}
      params_list.each do |p|
        only_selected_params[p] = params[p] if params.has_key?(p.to_s)
      end
      return only_selected_params
    end
    
    # Videos
    
    get '/videos.*' do
      display_response Video.find(:all), params[:splat].first
    end
    
    get '/videos/:key.*' do
      display_response(Video.find(params[:key]), params[:splat].first)
    end
    
    # HTML uplaod method where video data is uploaded directly
    # TODO: allow url param with location of external video
    # Allows both /videos.json and /videos.html
    post '/videos.*' do
      # puts params.inspect
      # puts request.env.inspect
      request.env['panda.iframe'] = params[:iframe].to_bool
      
      required_params(params, :upload_redirect_url, :state_update_url)
      
      video = Video.create_from_upload(params[:file], params[:state_update_url],  params[:upload_redirect_url])
      
      if PANDA_ENV == :test
        video.upload_to_store
        video.queue_encodings
      else
        # run_later do # TODO: ensure run_later timeout is long enough
          video.upload_to_store
          video.queue_encodings
        # end
      end
      
      display_response(video, params[:splat].first)
    end
    
    put '/videos/:key.*' do
      video = Video.find(params[:key])
      video.update_attributes(select_params(params, :upload_redirect_url, :state_update_url, :thumbnail_position))
      display_response(video, params[:splat].first)
    end
    
    delete '/videos/:key.*' do 
      video = Video.find(params[:key])
      video.obliterate!
      status 200
    end
    
    # Profiles
    
    get '/profiles.*' do
      display_response(Profile.find(:all), params[:splat].first)
    end
    
    get '/profiles/:key.*' do
      display_response(Profile.find(params[:key]), params[:splat].first)
    end
    
    post '/profiles.*' do
      required_params(params, :width, :height, :category, :title, :extname, :command)
      profile = Profile.create(select_params(params, :width, :height, :category, :title, :extname, :command))
      display_response(profile, params[:splat].first)
    end
    
    put '/profiles/:key.*' do
      profile = Profile.find(params[:key])
      profile.update_attributes(select_params(params, :width, :height, :category, :title, :extname, :command))
      display_response(profile, params[:splat].first)
    end
    
    delete '/profiles/:key.*' do 
      profile = Profile.find(params[:key])
      raise(CannotDelete, "Couldn't delete Profile with ID=#{params[:key]} as it has associated encodings which must be deleted first") unless profile.encodings.empty?
      profile.destroy
      status 200
    end
  end
end

# run Panda::Core