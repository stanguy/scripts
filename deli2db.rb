#! /usr/bin/env ruby

require 'rexml/document'
#include REXML
require 'iconv'
conv = Iconv.new( "LATIN1", "UTF-8" )


Source_db = "/Users/seb/Library/Application Support/Delicious Library/Library Media Data.xml"

file = File.new( Source_db )
doc = REXML::Document.new( file )

uuids = doc.elements.collect( "library/shelves/shelf[@name='to-be-read']/linkto" ) do |x|
  x.attributes["uuid"]
end

#puts uuids.inspect

doc.elements.each("library/items/book") do |x|
  if not uuids.include? x.attributes["uuid"]
    next
  end
  title = conv.iconv( x.attributes["fullTitle"] )
  if x.attributes.has_key? "author" 
    author = conv.iconv( x.attributes["author"].sub("\n", ", ") )
    puts <<EOF
      <listitem>
	<para><citetitle>#{title}</citetitle>, #{author}</para>
      </listitem>
EOF
  else
    puts <<EOF
      <listitem>
        <para><citetitle>#{title}</citetitle></para>
      </listitem>
EOF
  end
end
