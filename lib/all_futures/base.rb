# frozen_string_literal: true

module AllFutures
  class RecordNotFound < StandardError; end

  class Base < ActiveEntity::Base
    prepend ::AllFutures::Callbacks
    extend ::ActiveModel::Naming
    extend ::AllFutures::Translation
    include ::AllFutures::Persist
    include ::AllFutures::Dirty
    include ::AllFutures::Timestamp
    include ::AllFutures::Versions
    include ::ActiveModel::Conversion
    include ::ActiveModel::SecurePassword
    include ::ActiveRecord::Integration
    include ::Kredis::Attributes

    attr_reader :created_at, :updated_at

    def initialize(attributes = {})
      attributes ||= {}
      attributes = attributes.attributes.transform_keys(&:to_sym) if attributes.is_a?(ActiveRecord::Base)
      attributes_for_super = attributes.key?(:id) ? attributes.except(:id).except(:created_at).except(:updated_at) : attributes

      super(attributes_for_super) do
        @id = attributes&.fetch(:id, nil) || SecureRandom.uuid
        @created_at = Time.current
        @updated_at = attributes&.fetch(:updated_at, Time.current)
        @redis_key = "#{self.class.name}:#{@id}"
        @new_record = !self.class.exists?(@id)

        @destroyed = false
        @previously_new_record = false
        @_versioning_enabled = self.class.versioning
        @_versions = {}
        @_current_version = nil

        @attributes.keys.each do |attr|
          define_singleton_method("#{attr}_changed?") { attribute_changed?(attr) }
          define_singleton_method("rollback_#{attr}") { rollback_attribute(attr) }
          define_singleton_method("rollback_#{attr}!") { rollback_attribute!(attr) }
          define_singleton_method("restore_#{attr}") { restore_attribute(attr) }
          define_singleton_method("restore_#{attr}!") { restore_attribute(attr) }
        end
      end
    end

    class << self
      def create(attributes = {})
        new(attributes).tap { |record| record.save }
      end

      def find(id)
        raise ActiveRecord::RecordNotFound.new("Couldn't find #{name} without an ID") unless id
        record = load_model(id)
        model = new record["attributes"].merge(id: id)
        load_versions(model, record)
        set_previous_attributes(model, record)
        model.instance_variable_set "@created_at", Time.zone.parse(record["created_at"])
        model.instance_variable_set "@updated_at", Time.zone.parse(record["updated_at"])
        model
      end

      def exists?(id)
        Kredis.redis.exists?("#{name}:#{id}")
      end

      def readonly_attribute?(name)
        _attr_readonly.include?(name.to_s)
      end

      private

      def load_model(id)
        record = Kredis.json("#{name}:#{id}").value
        raise AllFutures::RecordNotFound.new("Couldn't find #{name} with ID #{id}") unless record
        record
      end

      def set_previous_attributes(model, record)
        tracker = ActiveModel::AttributeMutationTracker.new(model.instance_variable_get("@attributes"))
        previous_values = tracker.instance_variable_get("@attributes").instance_variable_get("@attributes")
        previous_values.each do |key, attribute|
          original = attribute.instance_variable_get("@original_attribute")
          original.instance_variable_set "@value_before_type_cast", record["previous_attributes"][key]
        end
        model.instance_variable_set "@mutations_before_last_save", tracker
      end
    end

    def id
      new_record? ? nil : @id
    end

    def id=(value)
      raise FrozenError.new("can't modify id when persisted") unless new_record?
      @id = value.to_s
    end

    def to_dom_id
      [self.class.name.underscore.dasherize.gsub("/", "--"), id].join("-")
    end

    def to_s
      inspect
    end

    def to_h
      attributes
    end

    def reject
      attributes
    end

    private

    def _raise_unknown_attribute_error(attribute)
      raise ActiveModel::UnknownAttributeError.new(self, attribute)
    end
  end

  ActiveSupport.run_load_hooks(:all_futures, Base)
end
