# frozen_string_literal: true

module AllFutures
  class Base < ActiveEntity::Base
    prepend ::AllFutures::Callbacks
    include ::ActiveModel::Conversion
    include ::AllFutures::Persist
    include ::AllFutures::Dirty
    include ::Kredis::Attributes

    def initialize(attributes = {})
      # `active_entity/inheritance.rb:49` defaults `attributes` to `nil`, and our method signature has no effect
      attributes ||= {}

      # in order to avoid FrozenError: can't modify id when persisted in `id=`
      attributes_for_super = attributes.key?(:id) ? attributes.except(:id) : attributes
      super(attributes_for_super) do
        @id = attributes&.fetch(:id, nil) || SecureRandom.uuid
        @redis_key = "#{self.class.name}:#{@id}"
        @new_record = !self.class.exists?(@id)

        @destroyed = false
        @previously_new_record = false

        @attributes.keys.each do |attr|
          define_singleton_method("#{attr}_changed?") { attribute_changed?(attr) }
          define_singleton_method("rollback_#{attr}") { rollback_attribute(attr) }
          define_singleton_method("rollback_#{attr}!") { rollback_attribute!(attr) }
          define_singleton_method("restore_#{attr}") { restore_attribute(attr) }
          define_singleton_method("restore_#{attr}!") { restore_attribute(attr) }
        end
      end
    end

    def self.create(attributes = {})
      new(attributes).tap { |record| record.save }
    end

    def self.find(id)
      raise ActiveRecord::RecordNotFound.new("Couldn't find #{name} without an ID") unless id

      json = Kredis.json("#{name}:#{id}").value
      raise ActiveRecord::RecordNotFound.new("Couldn't find #{name} with ID #{id}") unless json

      new json.merge(id: id)
    end

    def self.exists?(id)
      Kredis.redis.exists?("#{name}:#{id}")
    end

    def self.readonly_attribute?(name)
      _attr_readonly.include?(name.to_s)
    end

    def id
      new_record? ? nil : @id
    end

    def id=(value)
      raise FrozenError.new("can't modify id when persisted") unless new_record?
      @id = value.to_s
    end

    def to_dom_id
      [self.class.name.tr("/", ":").underscore.dasherize, id].join("-")
    end

    def to_s
      inspect
    end

    def to_h
      attributes
    end

    private

    def _raise_unknown_attribute_error(attribute)
      raise ActiveModel::UnknownAttributeError.new(self, attribute)
    end
  end
end
