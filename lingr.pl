use strict;
use warnings;
use Encode;

use AnyEvent;
use AnyEvent::Lingr;
use Scalar::Util ();

use Irssi;

our %IRSSI = ( name => 'lingr' );

our $lingr;

sub cmd_base {
    my ($data, $server, $item) = @_;
    Irssi::command_runsub('lingr', $data, $server, $item);
}

sub cmd_start {
    if ($lingr) {
        Irssi::print("Lingr: ERROR: lingr session is already running");
        return;
    }

    my $user     = Irssi::settings_get_str('lingr_user');
    my $password = Irssi::settings_get_str('lingr_password');
    my $api_key  = Irssi::settings_get_str('lingr_apikey');

    unless ($user and $password) {
        Irssi::print("Lingr: lingr_user and lingr_password are required to /set");
        return;
    }

    $lingr = AnyEvent::Lingr->new(
        user     => $user,
        password => $password,
        $api_key ? (api_key => $api_key) : (),
    );

    $lingr->on_error(sub {
        my ($msg) = @_;
        return unless $lingr;

        if ($msg =~ /^596:/) {  # timeout
            $lingr->start_session;
        }
        else {
            Irssi::print("Lingr: ERROR: " . $msg);
            my $t; $t = AnyEvent->timer(
                after => 5,
                cb => sub {
                    undef $t;
                    $lingr->start_session if $lingr;
                },
            );
        }
    });

    $lingr->on_room_info(sub {
        my ($rooms) = @_;
        return unless $lingr;

        for my $room (@$rooms) {
            my $win_name = 'lingr/' . $room->{id};
            my $win = Irssi::window_find_name($win_name);
            unless ($win) {
                Irssi::print("Lingr: creating window: " . $win_name);
                $win = Irssi::Windowitem::window_create($win_name, 1);
                $win->set_name($win_name);
            }
        }
    });

    $lingr->on_event(sub {
        my ($event) = @_;

        if (my $msg = $event->{message}) {
            my $win_name = 'lingr/' . $msg->{room};
            my $win = Irssi::window_find_name($win_name);
            $win->print(sprintf "%s: %s",
                        encode_utf8($msg->{nickname}), encode_utf8($msg->{text}));
        }
    });

    $lingr->start_session;
}

sub cmd_stop {
    undef $lingr;
}

sub sig_send_text {
    my ($line, $server, $win) = @_;

    if (!$win) {
        $win = Irssi::active_win();
    }

    my ($room) = $win->{name} =~ m!^lingr/(.*)$!;
    if ($room && $lingr) {
        $lingr->say(decode_utf8($room), decode_utf8($line));
    }
}

Irssi::command_bind('lingr', \&cmd_base);
Irssi::command_bind('lingr start', \&cmd_start);
Irssi::command_bind('lingr stop', \&cmd_stop);

Irssi::settings_add_str('lingr', 'lingr_user', q[]);
Irssi::settings_add_str('lingr', 'lingr_password', q[]);
Irssi::settings_add_str('lingr', 'lingr_apikey', q[]);

Irssi::signal_add_last('send text', \&sig_send_text);
