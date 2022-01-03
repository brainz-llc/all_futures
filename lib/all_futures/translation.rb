# frozen_string_literal: true

module AllFutures
  module Translation
    include ActiveModel::Translation

    def lookup_ancestors
      klass = self
      classes = [klass]
      return classes if klass == AllFutures::Base

      until klass.base_class?
        classes << klass = klass.superclass
      end
      classes
    end

    def i18n_scope
      :allfutures
    end
  end
end
