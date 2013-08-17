package Tweet500pxPhotostream::Tags;
use strict;

use Tweet500pxPhotostream::Util;

sub _hdlr_500px_shorter_url {
    my ( $ctx, $args, $cond ) = @_;
    if ( my $photo_id = $args->{ photo_id } ) {
        if ( $photo_id =~ /^[0-9]{1,}$/ ) {
            return Tweet500pxPhotostream::Util::shorter_url( $photo_id ) || '';
        }
    }
    return '';
}

1;
