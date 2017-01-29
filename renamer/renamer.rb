#! /usr/bin/env ruby

require 'epub/parser'
require 'pdf/reader'
require 'pp'
require 'optparse'

def handle_epub(bookfile)
  book = EPUB::Parser.parse(bookfile)
  
  title = book.metadata.titles.first.content.tr ':/', ",,"
  
  author_list = book.metadata.creators.map { |author| author.content.strip }.find_all { |author| ! author.empty? }
  if author_list.size > 3
    author_list = author_list[0..2] << "..."
  end
  authors = author_list.join(", ")

  if authors.empty?
    "#{title}.epub"
  else
    "#{title} (#{authors}).epub"
  end
  
rescue Archive::Zip::ExtraFieldError => e
  STDERR.puts "Could not parse #{bookfile} (zip extra field)"
end

def handle_pdf(bookfile)
  book = PDF::Reader.open(bookfile) do |reader|
    title = reader.info[:Title]
    author = reader.info[:Author]
    if author.empty?
      "#{title} (#{author}).pdf"
    elsif title.empty?
      nil
    else
      "#{title} (#{author}).pdf"
    end
  end
end

print_mode = false

OptionParser.new do |opts|
  opts.on("-p") do |v|
    print_mode = true
  end
end.parse!

ARGV.each do |bookfile|
  next if File.directory?(bookfile)
  begin
    directory = File.dirname(bookfile)
    newfile = case bookfile
              when /\.epub$/
                handle_epub(bookfile)
              when /\.pdf$/
                handle_pdf(bookfile)
              else
                STDERR.puts "Unable to handle #{bookfile}"
                nil
              end
    unless newfile.nil?
      newfile = directory + "/" + newfile
      if print_mode
        puts "#{bookfile}\t#{newfile}"
      else
        File.rename(bookfile,newfile)
      end
    end
  rescue Exception => e
    STDERR.puts "Could not parse #{bookfile} : #{e.class}"
  end
end
