class Admin::ElementsController < AlchemyController
  
  layout 'alchemy'
  
  before_filter :set_translation
  
  @@date_parts = ["%Y", "%m", "%d", "%H", "%M"]
  
  filter_access_to [:new, :create, :order, :index], :attribute_check => false
  
  def index
    @page_id = params[:page_id]
    if @page_id.blank? && !params[:page_urlname].blank?
      @page_id = Page.find_by_urlname(params[:page_urlname]).id
    end
    @elements = Element.find_all_by_page_id_and_public(@page_id, true)
  end
  
  def list
    @page = Page.find(
      params[:page_id],
      :include => {
        :elements => :contents
      }
    )
    render :layout => false
  end
  
  def new
    @page = Page.find_by_id(params[:page_id])
    @element = @page.elements.build
    @elements = Element.all_for_layout(@page, @page.page_layout)
    render :layout => false
  end
  
  # Creates a element as discribed in config/alchemy/elements.yml on page via AJAX.
  # If a Ferret::FileNotFoundError raises we catch it and rebuilding the index.
  def create
    if params[:element][:name] == "paste_from_clipboard"
      @element = Element.send(session[:clipboard][:method].to_sym, Element.find(session[:clipboard][:element_id]), {:page_id => params[:element][:page_id]})
      session[:clipboard][:method] == 'move' ? session[:clipboard] = {} : nil
    else
      @element = Element.new_from_scratch(params[:element])
    end
    @page = @element.page
    if @element.save
      @richtext_contents = @element.contents.select { |content| content.essence_type == 'EssenceRichtext' }
      # rendering via rjs template
    else
      render_remote_errors(@element)
    end
  rescue Exception => e
    exception_handler(e)
  end
  
  # If a Ferret::FileNotFoundError raises we catch it and rebuilding the index.
  # TODO: refactor this bastard. i bet to shrink this to 4 rows.
  def update
    @element = Element.find_by_id(params[:id])
    begin
      #save all contents in this element
      for content in @element.contents
        # this is so god damn ugly. can't wait for rails 2.3 and multiple updates for nested forms
        if content.essence_type == "EssenceText"
          # downwards compatibility
          unless params[:contents].blank?
            unless params[:contents]["content_#{content.id}"].blank?
              if params[:contents]["content_#{content.id}"]["body"].nil?
                content.essence.body = params[:contents]["content_#{content.id}"].to_s
              else
                content.essence.body = params[:contents]["content_#{content.id}"]["body"].to_s
              end
            #
            content.essence.link = params[:contents]["content_#{content.id}"]["link"].to_s
            content.essence.title = params[:contents]["content_#{content.id}"]["title"].to_s
            content.essence.link_class_name = params[:contents]["content_#{content.id}"]["link_class_name"].to_s
            content.essence.open_link_in_new_window = params[:contents]["content_#{content.id}"]["open_link_in_new_window"] == 1 ? true : false
            content.essence.public = !params["public"].nil?
            content.essence.save!
            end
          end
        elsif content.essence_type == "EssenceRichtext"
          content.essence.body = params[:contents]["content_#{content.id}"]
          content.essence.public = !params["public"].nil?
          content.essence.save!
        elsif content.essence_type == "EssenceHtml"
          content.essence.source = params[:contents]["content_#{content.id}"]["source"].to_s
          content.essence.save!
        elsif content.essence_type == "EssenceDate"
          content.essence.date = DateTime.strptime(params[:date].values.join('-'), @@date_parts[0, params[:date].length].join("-"))
          content.essence.save!
        elsif content.essence_type == "EssencePicture"
          content.essence.link = params[:contents]["content_#{content.id}"]["link"]
          content.essence.link_title = params[:contents]["content_#{content.id}"]["link_title"]
          content.essence.link_class_name = params[:contents]["content_#{content.id}"]["link_class_name"]
          content.essence.open_link_in_new_window = params[:contents]["content_#{content.id}"]["open_link_in_new_window"]
          content.essence.picture_id = params[:contents]["content_#{content.id}"]["picture_id"]
          content.essence.caption = params[:images]["caption_#{content.essence.id}"] unless params[:images].nil?
          content.essence.save!
        end
      end
      # update the updated_at and updated_by values for the page this element lies on.
      @page = @element.page
      @element.public = !params[:public].nil?
      @element.save!
      @richtext_contents = @element.contents.select { |content| content.essence_type == 'EssenceRichtext' }
    rescue Exception => e
      exception_logger(e)
      # Rebuilding the ferret search engine indexes, if Ferret::FileNotFoundError raises
      if e.class == Ferret::FileNotFoundError
        EssenceText.rebuild_index
        EssenceRichtext.rebuild_index
        render :update do |page|
          Alchemy::Notice.show(page, _("Index Error after saving Element. Please try again!"), :error)
        end
      # Displaying error notice
      else
        show_error_notice(e)
      end
    end
  end
  
  # Deletes the element with ajax and sets session[:clipboard].nil
  def destroy
    @element = Element.find_by_id(params[:id])
    @page = @element.page
    if @element.destroy
      unless session[:clipboard].nil?
        session[:clipboard] = nil if session[:clipboard][:element_id] == params[:id]
      end
    end
  rescue Exception => e
    exception_handler(e)
  end
  
  # Copies a element to the clipboard in the session
  def copy_to_clipboard
    @element = Element.find(params[:id])
    session[:clipboard] = {}
    session[:clipboard][:method] = params[:method]
    session[:clipboard][:element_id] = @element.id
    if session[:clipboard][:method] == "move"
      @element.page_id = nil
      @element.save!
    end
  rescue Exception => e
    exception_handler(e)
  end
  
  def order
    for element in params[:element_ids]
      element = Element.find(element)
      element.move_to_bottom
    end
    render :update do |page|
      Alchemy::Notice.show(page, _("successfully_saved_element_position"))
      page << "Alchemy.reloadPreview();"
    end
  rescue Exception => e
    exception_handler(e)
  end
  
  def fold
    @element = Element.find(params[:id])
    @element.folded = !@element.folded
    @element.save(false)
    @richtext_contents = @element.contents.select { |content| content.essence_type == 'EssenceRichtext' }
  rescue Exception => e
    exception_handler(e)
  end
  
end
