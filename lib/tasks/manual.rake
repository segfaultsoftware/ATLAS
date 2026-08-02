namespace :manual do
  desc "Import a UTF-8 text file into an existing Manual page"
  task :import, [ :slug, :source_path ] => :environment do |_, args|
    abort "Usage: bin/rails 'manual:import[slug,source_path]'" unless args[:slug] && args[:source_path]

    page = ManualPage.find_by!(slug: args[:slug])
    ManualPageImporter.call(page:, source_path: args[:source_path])
    puts "Imported #{args[:source_path]} into Manual page #{page.slug}."
  end

  desc "Export a Manual page's content to a text file"
  task :export, [ :slug, :destination_path ] => :environment do |_, args|
    abort "Usage: bin/rails 'manual:export[slug,destination_path]'" unless args[:slug] && args[:destination_path]

    page = ManualPage.find_by!(slug: args[:slug])
    ManualPageExporter.call(page:, destination_path: args[:destination_path])
    puts "Exported Manual page #{page.slug} to #{args[:destination_path]}."
  end
end
