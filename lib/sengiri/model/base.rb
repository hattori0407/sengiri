module Sengiri
  module Model
    class Base < ActiveRecord::Base
      self.abstract_class = true
      attr_reader :current_shard

      def initialize(attributes = nil, options = {})
        @shard_name = self.class.shard_name
        super
      end

      def sharding_group_name
        self.class.instance_variable_get :@sharding_group_name
      end

      def shard_name
        self.class.instance_variable_get :@shard_name
      end

      class << self
        def shard_name         ; @shard_name          end
        def sharding_group_name; @sharding_group_name end

        def shard_classes
          return @shard_class_hash.values if @shard_class_hash
          []
        end

        def sharding_group(name, confs=nil)
          @dbconfs = confs if confs
          @sharding_group_name = name
          @shard_class_hash = {}
          first = true
          shard_names.each do |s|
            klass = Class.new(self)
            Object.const_set self.name + s, klass
            klass.instance_variable_set :@shard_name, s
            klass.instance_variable_set :@dbconfs,    dbconfs
            klass.instance_variable_set :@sharding_group_name, name
            #
            # first shard shares connection with base class
            #
            if first
              establish_shard_connection s
            else
              klass.establish_shard_connection s
            end
            first = false
            if defined? Ardisconnector::Middleware
              Ardisconnector::Middleware.models << klass
            end
            @shard_class_hash[s] = klass
          end
        end

        def dbconfs
          if defined? Rails
            @dbconfs ||= Rails.application.config.database_configuration.select {|name| /^#{@sharding_group_name}/ =~ name }

          end
          @dbconfs
        end

        def shard_names
          @shard_names ||= dbconfs.map do |k,v|
            k.gsub("#{@sharding_group_name}_shards_", '')
          end
          @shard_names
        end

        def shard(name)
          if block_given?
            yield @shard_class_hash[name.to_s]
          end
          @shard_class_hash[name.to_s]
        end

        def shards(&block)
          transaction do
            shard_names.each do |shard_name|
              block.call shard(shard_name)
            end
          end
        end

        def transaction(klasses=shard_classes, &block)
          if shard_name
            super &block
          else
            if klasses.length > 0
              klass = klasses.pop
              klass.transaction do
                transaction klasses, &block
              end
            else
              yield
            end
          end
        end

        def establish_shard_connection(name)
          establish_connection dbconfs["#{@sharding_group_name}_shards_#{name}"]
        end
      end
    end
  end
end