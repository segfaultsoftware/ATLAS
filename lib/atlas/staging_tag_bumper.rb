require_relative "tag_bumper"

module Atlas
  class StagingTagBumper < TagBumper
    STAGING_REF = DeploymentAutomation::STAGING_REF

    def initialize(**options)
      super(**options.merge(tag_ref: STAGING_REF, target_label: "staging"))
    end
  end
end
