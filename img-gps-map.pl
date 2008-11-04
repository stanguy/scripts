#! /usr/bin/perl -w 

use strict;

use Image::ExifTool;


package Image::ExifTool;

use warnings;
use strict;
use Carp;
use Image::ExifTool;

my @LOC_TAGS = qw(
  GPSLatitude     GPSLatitudeRef
  GPSLongitude    GPSLongitudeRef
);

my @ELE_TAGS = qw(
  GPSAltitude     GPSAltitudeRef
);

my @GROUP = ( Group => 'GPS' );

sub _has_all {
    my $self = shift;
    for ( @_ ) {
        return unless defined( $self->GetValue( $_ ) );
    }
    return 1;
}

sub HasLocation {
    my $self = shift;
    return $self->_has_all( @LOC_TAGS );
}

sub HasElevation {
    my $self = shift;
    return $self->_has_all( @ELE_TAGS );
}

sub _set_latlon {
    my $self = shift;
    my ( $name, $latlon, @sign_flags ) = @_;

    $self->SetNewValue( $name, abs( $latlon ), @GROUP, Type => 'ValueConv' );
    $self->SetNewValue(
        $name . 'Ref',
        $sign_flags[ $latlon < 0 ],
        @GROUP, Type => 'ValueConv'
    );
}

sub SetLocation {
    my $self = shift;
    my ( $lat, $lon ) = @_;

    croak "SetLocation must be called with the latitude and longitude"
      unless defined( $lon );

    $self->_set_latlon( 'GPSLatitude',  $lat, qw(N S) );
    $self->_set_latlon( 'GPSLongitude', $lon, qw(E W) );
}

sub SetElevation {
    my $self = shift;
    my ( $ele ) = @_;

    croak "SetElevation must be called with the elevation in metres"
      unless defined( $ele );

    $self->SetNewValue( 'GPSAltitude', abs( $ele ),
        @GROUP, Type => 'ValueConv' );
    $self->SetNewValue( 'GPSAltitudeRef', $ele < 0 ? '1' : '0',
        @GROUP, Type => 'ValueConv' );
}

sub GetLocation {
    my $self = shift;

    wantarray or croak "GetLocation must be called in a list context";
    return
      map { $self->GetValue( $_, 'ValueConv' ) } qw(GPSLatitude GPSLongitude);
}

sub GetElevation {
    my $self = shift;
    my $v    = $self->GetValue( 'GPSAltitude', 'Raw' );
    my $r    = $self->GetValue( 'GPSAltitudeRef', 'Raw' );

    return unless defined( $v ) && defined( $r );
    return $v * ( $r == 0 ? 1 : -1 );
}

package Main;

use Data::Dumper;
use Time::Local;

# first, read the waypoints

sub GpxDate2Ts($) {
  my $str = shift;
  my %months = ( OCT => 10 -1 );
  #                day       month     year     hour       mins    sec
  if ( $str =~ /^(\d{2})-([A-Z]{3})-(\d{2}) (\d{1,2}):(\d{2}):(\d{2})([AP]M)?$/ ) {
    return timegm( $6, $5, $4, $1, $months{$2}, 2000 + $3 );
  } else {
    die "Unable to parse date $str";
  }
}

use XML::TreePP;
my $tpp = XML::TreePP->new();
my $tree = $tpp->parsefile( "gpsbabel_output.gpx" );
my @waypoints;
foreach my $wpt ( @{$tree->{'gpx'}->{'wpt'}} ) {
  next if $wpt->{'name'} !~ /^\d+$/;
  push @waypoints, {
		    LAT => $wpt->{'-lat'},
		    LON => $wpt->{'-lon'},
		    ELE => $wpt->{'ele'},
		    DATE => GpxDate2Ts( $wpt->{'cmt'} )
		   };
#  print scalar localtime( $waypoints[-1]->{DATE} ),"\n";
} 

#print Dumper \@waypoints;

sub ExifDate2Ts($) {
  my $str = shift;
  my %months = ( OCT => 10 -1 );
  #               year    month   day     hour     mins    sec
  if ( $str =~ /^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})$/ ) {
    return timegm( $6, $5, $4, $3, $2-1, $1 );
  } else {
    die "Unable to parse date $str";
  }
}

sub findWptByDate($$) {
  my( $date_str, $waypoints ) = @_;
  my $date = ExifDate2Ts( $date_str );
#  print scalar localtime( $date ),"\n";
  my @date_dists;
  foreach my $wpt ( @{$waypoints} ) {
    push @date_dists, abs( $wpt->{DATE} - $date );
  }
#  print Dumper \@date_dists;
  my $i = 0;
  my $min = 2**31;
  my $min_idx = -1;
  while ( $i < $#waypoints ) {
    if ( $date_dists[$i] < $min ) {
      $min = $date_dists[$i];
      $min_idx = $i;
    }
    ++$i;
  }
#  print "min is $min, idx is $min_idx\n";
  return $waypoints->[$min_idx];
}

use POSIX;

foreach my $filename ( glob "/tmp/gps/*.jpg" ) {
  my $info = new Image::ExifTool;

  $info->ExtractInfo( $filename )
    or die "Unable to read exif data from image";

  my @tags = $info->GetFoundTags('File');

#  print Dumper \@tags;
  my $desc = $info->GetValue( "ImageDescription" );
  print "description: ", $desc,"\n";
  my $date = $info->GetValue( "DateTimeOriginal", 'ValueConv' );
  print "date: ", $date,"\n";
  my $wpt = findWptByDate( $date, \@waypoints );
  print "closest waypoint is ", strftime( '%Y:%m:%d %H:%M:%S', gmtime( $wpt->{DATE} ) ), "\n";
#  last;
  $info->SetNewValue( "ImageDescription", $desc, DelValue => 1 );
  #  or die "unable to set value" ;
  
  $info->SetLocation( $wpt->{LAT}, $wpt->{LON} );
  $info->SetElevation( $wpt->{ELE} );
  $info->WriteInfo( $filename );
}

