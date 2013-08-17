package Tweet500pxPhotostream::Util;
use strict;

use Digest::SHA1 qw( sha1_base64 );
use Net::OAuth;
use HTML::TreeBuilder;

sub tweet_500px_photostream_by_id {
    my ( $photo_id, $blog_id ) = @_;
    return unless $photo_id;
    return unless $blog_id;
    my $plugin = MT->component( 'Tweet500pxPhotostream' );
    my $shorter_url = shorter_url( $photo_id );
    my $ua = MT->new_ua;
    my $req = HTTP::Request->new( GET => $shorter_url ) or return;
    my $res = $ua->request( $req ) or return;
    if ( $res->is_success ) {
        my $content = $res->decoded_content;
        my $tree = HTML::TreeBuilder->new;
        $tree->parse( $content );
        my ( $author, $title );
        for my $meta ( $tree->find( 'meta' ) ) {
            my $property = $meta->attr( 'property' );
            next unless $property;
            if ( $property eq 'og:title' ) {
                $title = $meta->attr( 'content' );
                $title = MT::I18N::utf8_off( $title );
            }
        }
        if ( my $element_username = $tree->look_down( "class", "author_name" ) ) {
            my $element_author = $element_username->find( 'a' );
            $author = $element_author->as_text;
            $author = MT::I18N::utf8_off( $author );
        }
        my $scope = 'blog:' . $blog_id;
        my $tweet = $plugin->get_config_value( 'tweet_format', $scope );
        $tweet = MT::I18N::utf8_off( $tweet );
        my $search_shorter_url = quotemeta( '*shorter_url*' );
        my $search_title = quotemeta( '*title*' );
        my $search_author = quotemeta( '*author*' );
        $tweet =~ s/$search_shorter_url/$shorter_url/g;
        $tweet =~ s/$search_title/$title/g;
        $tweet =~ s/$search_author/$author/g;
        print $tweet . "\n";
        if ( my $res = update_twitter( $tweet, $blog_id ) ) {
            my $log_message = $plugin->translate( 'Update twitter success: [_1]', $res );
            return success_log( $log_message, $blog_id );
        }
    }
}

sub update_twitter {
	my ( $msg, $blog_id ) = @_;
	my $plugin = MT->component( 'Tweet500pxPhotostream' );
    $msg = MT::I18N::decode_utf8( $msg );

	my $url  = 'https://api.twitter.com/1.1/statuses/update.json';
    my $request_method = 'POST';

    my $request  = Net::OAuth->request( "protected resource" )->new(
        consumer_key => $plugin->get_config_value( 'consumer_key' ),
        consumer_secret => $plugin->get_config_value( 'consumer_secret' ),
        request_url => $url,
        request_method => $request_method,
        signature_method => 'HMAC-SHA1',
        timestamp => time(),
        nonce => sha1_base64( time() . $$ . rand() ),
        token => $plugin->get_config_value( 'access_token', 'blog:' . $blog_id ),
        token_secret => $plugin->get_config_value( 'access_token_secret', 'blog:' . $blog_id ),
        extra_params => {
            status => $msg,
        },
    );
    $request->sign;
    $request->verify;

    my $ua = LWP::UserAgent->new;
    my $http_header = HTTP::Headers->new( 'User-Agent' => $plugin->name );
    my $http_request = HTTP::Request->new( $request_method, $url, $http_header, $request->to_post_body );
    $http_request->content_type( 'application/x-www-form-urlencoded' ); # Required in API version 1.1
    my $response = $ua->request( $http_request );

	unless ( $response->is_success ) {
	    return $plugin->trans_error( "Failed to get response from [_1], ([_2])", "twitter", $response->status_line );
	}
	return $msg;
}

sub shorter_url {
    my ( $photo_id ) = @_;
    return unless $photo_id;
    if ( $photo_id =~ /^[0-9]{1,}$/ ) {
        return 'http://500px.com/photo/' . $photo_id;
    }
    return '';
}

sub rss_url {
    my ( $user_id ) = @_;
    if ( $user_id ) {
        return 'http://500px.com/' . $user_id . '/rss';
    }
}


sub success_log {
    my ( $message, $blog_id ) = @_;
    return save_log( $message, $blog_id, MT::Log::INFO() );
}

sub error_log {
    my ( $message, $blog_id ) = @_;
    return save_log( $message, $blog_id, MT::Log::ERROR() );
}

sub save_log {
    my ( $message, $blog_id, $log_level ) = @_;
    if ( $message ) {
        my $plugin = MT->component( 'Tweet500pxPhotostream' );
        my $log = MT::Log->new;
        $log->message( $message );
        $log->class( lc( $plugin->id ) );
        $log->blog_id( $blog_id );
        $log->level( $log_level );
        $log->save or die $log->errstr;
        return $log;
    }
}

1;
