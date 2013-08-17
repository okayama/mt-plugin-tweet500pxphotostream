package Tweet500pxPhotostream::Tasks;
use strict;

use Encode;
use XML::Simple;
use MT::AtomServer;
use Tweet500pxPhotostream::Util;
use HTTP::Date;

sub tweet_500px_photostream {
    my $plugin = MT->component( 'Tweet500pxPhotostream' );
    my @blogs = MT->model( 'blog' )->load( undef, { no_class => 1, } );
    for my $blog ( @blogs ) {
        my $blog_id = $blog->id;
        my $scope = 'blog:' . $blog_id;
        if ( my $user_id = $plugin->get_config_value( 'user_id', $scope ) ) {
            if ( my $rss_url = Tweet500pxPhotostream::Util::rss_url( $user_id ) ) {
                my $tweet_format = $plugin->get_config_value( 'tweet_format', $scope );
                my $last_updated = $plugin->get_config_value( 'last_updated', $scope );
                my $tweet_limit = $plugin->get_config_value( 'tweet_limit', $scope );
                if ( my $tweets = _get_tweet( $blog_id, $rss_url, $tweet_format, $last_updated, $tweet_limit ) ) {
                    for my $tweet ( @$tweets ) {
                       if ( my $res = Tweet500pxPhotostream::Util::update_twitter( $tweet, $blog_id ) ) {
                            my $log_message = $plugin->translate( 'Update twitter success: [_1]', $res );
                            Tweet500pxPhotostream::Util::success_log( $log_message, $blog_id );
                       }
                    }
                }
            }
        }
    }
}

sub _get_tweet {
    my ( $blog_id, $rss_url, $format, $last_updated, $limit ) = @_;
    return unless $blog_id;
    return unless $rss_url;
    return unless $format;
    my $plugin = MT->component( 'Tweet500pxPhotostream' );
    my $ua = MT->new_ua;
    my $req = HTTP::Request->new( GET => $rss_url ) or return;
    my $res = $ua->request( $req ) or return;
    if ( $res->is_success ) {
        my $content = $res->content;
        my $ref = XMLin( $content, NormaliseSpace => 2 );
        my $author = $ref->{ channel }->{ title } or return;
        $author =~ s!^500px\s/\s!!;
        my $items = $ref->{ channel }->{ item } or return;
        my @items = sort { str2time( $a->{ pubDate } ) cmp str2time( $b->{ pubDate } ) } @$items;
        my @tweets;
        my $i = 0;
        for my $item ( @items ) {
            my $updated = $item->{ pubDate };
            my $updated_epoch = str2time( $updated );
            if ( $last_updated && ( $updated_epoch <= $last_updated ) ) {
                next;
            }
            if ( my $photo_id = $item->{ 'link' } ) {
                $photo_id =~ s!.*/([0-9]{1,})!$1!;
                if ( my $shorter_url = Tweet500pxPhotostream::Util::shorter_url( $photo_id ) ) {
                    my $tweet = $format;
                    my $title = $item->{ title };
                    $tweet = MT::I18N::decode_utf8( $tweet );
                    $title = MT::I18N::decode_utf8( $title );
                    $author = MT::I18N::decode_utf8( $author );
                    my $search_shorter_url = quotemeta( '*shorter_url*' );
                    my $search_title = quotemeta( '*title*' );
                    my $search_author = quotemeta( '*author*' );
                    $tweet =~ s/$search_shorter_url/$shorter_url/g;
                    $tweet =~ s/$search_title/$title/g;
                    $tweet =~ s/$search_author/$author/g;
                    push( @tweets, $tweet );
                }
            }
            $i++;
            if ( $i eq $limit || $i == scalar( @items ) ) {
                $last_updated = $updated_epoch;
                last;
            }
        }
        my $scope = 'blog:' . $blog_id;
        $plugin->set_config_value( 'last_updated', $last_updated, $scope );
        return \@tweets;
    }
    return 0;
}

1;
