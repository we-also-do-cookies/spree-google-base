require 'net/ftp'

module SpreeGoogleBase
  class FeedBuilder
    include Spree::Core::Engine.routes.url_helpers

    attr_reader :store, :domain, :title

    def self.generate_and_transfer
      self.builders.each do |builder|
        builder.generate_and_transfer_store
      end
    end

    def self.builders
      if defined?(Spree::Store)
        Spree::Store.all.map{ |store| self.new(:store => store) }
      else
        [self.new]
      end
    end

    def initialize(opts = {})
      raise "Please pass a public address as the second argument, or configure :public_path in Spree::GoogleBase::Config" unless
        opts[:store].present? or (opts[:path].present? or Spree::GoogleBase::Config[:public_domain])

      @store = opts[:store] if opts[:store].present?
      @title = @store ? @store.name : Spree::GoogleBase::Config[:store_name]

      @domain = @store ? @store.domains.match(/[\w\.]+/).to_s : opts[:path]
      @domain ||= Spree::GoogleBase::Config[:public_domain]
    end

    def ar_scope
      if @store
        Spree::Product.by_store(@store).google_base_scope.scoped
      else
        Spree::Product.google_base_scope.scoped
      end
    end

    def generate_and_transfer_store
      delete_xml_if_exists

      File.open(path, 'w') do |file|
        generate_xml file
      end

      transfer_xml
      cleanup_xml
    end

    def path
      "#{::Rails.root}/public/#{filename}"
    end

    def filename
      "google_base_v#{@store.try(:code)}.xml"
    end

    def delete_xml_if_exists
      File.delete(path) if File.exists?(path)
    end

    def generate_xml output
      xml = Builder::XmlMarkup.new(:target => output)
      xml.instruct!

      xml.rss(:version => '2.0', :"xmlns:g" => "http://base.google.com/ns/1.0") do
        xml.channel do
          build_meta(xml)

          ar_scope.find_each(:batch_size => 300) do |product|
            build_product(xml, product) if product.is_active?
          end
        end
      end
    end

    def transfer_xml
      raise "Please configure your Google Base :ftp_username and :ftp_password by configuring Spree::GoogleBase::Config" unless
        Spree::GoogleBase::Config[:ftp_username] and Spree::GoogleBase::Config[:ftp_password]

      ftp = Net::FTP.new('uploads.google.com')
      ftp.passive = true
      ftp.login(Spree::GoogleBase::Config[:ftp_username], Spree::GoogleBase::Config[:ftp_password])
      ftp.put(path, filename)
      ftp.quit
    end

    def cleanup_xml
      #File.delete(path)
    end

    def build_product(xml, product)
      xml.item do
        xml.tag!('link', "http://www.paperfly.co.uk" + product.permalink)
        build_images(xml, product)

        GOOGLE_BASE_ATTR_MAP.each do |k, v|
          value = product.send(v)
          xml.tag!(k, value.to_s) if value.present?
        end
      end
    end

    def build_images(xml, product)
      main_image, *more_images = product.master.images

      return unless main_image
      xml.tag!('g:image_link', image_url(main_image))

      more_images.each do |image|
        xml.tag!('g:additional_image_link', image_url(image))
      end
    end

    def image_url image
      base_url = image.attachment.url(:large)
      base_url = "#{domain}/#{base_url}" unless Spree::Config[:use_s3]

      base_url
    end

    def build_meta(xml)
      xml.title @title
      xml.link @domain
    end

  end
end
