# frozen_string_literal: true

module AllFutures
  class Base < ActiveEntity::Base
    prepend ::AllFutures::Callbacks
    include ActiveModel::Conversion

    def initialize(attributes = {})
      super do
        extend(::AllFutures::Persist)
        extend(::AllFutures::Dirty)

        @id ||= SecureRandom.uuid
        @redis_key = "#{self.class.name}:#{@id}"
        @new_record = !Kredis.redis.exists?(@redis_key)

        @destroyed = false
        @previously_new_record = false
        @_trigger_destroy_callback = false
        @_trigger_update_callback = false

        @attributes.keys.each do |attr|
          define_singleton_method("saved_change_to_#{attr}?") { saved_change_to_attribute?(attr) }
          define_singleton_method("saved_change_to_#{attr}") { saved_change_to_attribute?(attr) ? [attribute_previously_was(attr), attribute_was(attr)] : nil }
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

    def id
      new_record? ? nil : @id
    end

    def id=(value)
      raise FrozenError.new("can't modify id when persisted") unless new_record?
      @id = value.to_s
    end
  end
end
