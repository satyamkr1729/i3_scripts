#!/usr/bin/env python

import sys
import dbus
import argparse
import time
import logging
import signal

player = None

parser = argparse.ArgumentParser()
parser.add_argument(
    '-t',
    '--trunclen',
    type=int,
    metavar='trunclen'
)
parser.add_argument(
    '-f',
    '--format',
    type=str,
    metavar='custom format',
    dest='custom_format'
)

parser.add_argument(
    '--font',
    type=str,
    metavar='the index of the font to use for the main label',
    dest='font'
)
parser.add_argument(
    '-q',
    '--quiet',
    action='store_true',
    dest='quiet',
)

parser.add_argument(
        '-d',
        '--debug',
        action = 'store_true',
        dest = 'debug'
)

args = parser.parse_args()

def playerControl(signalVal, stack):
    global player
    logger.debug(f"Received  signal {signal}")
    if player == None:
        return
    try:
        if signalVal == signal.SIGRTMIN + 1:
            logging.debug("got play pause signal")
            player.PlayPause()
        elif signalVal == signal.SIGRTMIN + 2:
            logging.debug("got play next signal")
            player.Next()
        elif signalVal == signal.SIGRTMIN + 3:
            logging.debug("got play previous signal")
            player.Previous()
    except Exception:
        logger.exception("Failed to play-pause on the player")

def fix_string(string):
    # corrects encoding for the python version used
    if sys.version_info.major == 3:
        return string
    else:
        return string.encode('utf-8')


def truncate(name, trunclen):
    if len(name) > trunclen:
        name = name[:trunclen]
        #name += '...'
        #if ('(' in name) and (')' not in name):
        #    name += ')'
    return name

def colorize(text, status):
    text = truncate(text, trunclen)
    if status == "Playing":
        #return f"%{{F{playing_text_color}}}%{{u{playing_underline_color}}}%{{+u}}{text}%{{-u}}%{{u-}}%{{F-}}"
        return f"%{{u{playing_underline_color}}}%{{+u}}{text}%{{-u}}%{{u-}}"
    else:
        return f"%{{+u}}{text}%{{-u}}"

# Default parameters
playing_text_color = '#a1fba1'
playing_underline_color = '#61C766'
output = fix_string(u'{artist}: {song}')
trunclen = 50
no_player_label = "Launch Spotify to Play"
label_with_font = '%{{T{font}}}{label}%{{T-}}'

font = args.font
quiet = args.quiet

if args.debug:
    logging.basicConfig(format='[%(levelname)s]: %(msg)s', level=logging.DEBUG)
else:
    logging.basicConfig(format='[%(levelname)s]: %(msg)s')

logger = logging.getLogger("main")

# parameters can be overwritten by args
if args.trunclen is not None:
    trunclen = args.trunclen
if args.custom_format is not None:
    output = args.custom_format

if font:
    no_player_label = label_with_font.format(font=font, label=no_player_label)

def main():
    global player
    try:
        logger.debug("Getting session bus")
        session_bus = dbus.SessionBus()
        logger.debug("Getting spotify bus")
        spotify_bus = session_bus.get_object(
            'org.mpris.MediaPlayer2.spotify',
            '/org/mpris/MediaPlayer2'
        )

        original_label = no_player_label
        rolled_label = no_player_label

        player = dbus.Interface(
                spotify_bus,
                'org.mpris.MediaPlayer2.Player'
        )

        signal.signal(signal.SIGRTMIN + 1, playerControl)
        signal.signal(signal.SIGRTMIN + 2, playerControl)
        signal.signal(signal.SIGRTMIN + 3, playerControl)

        hasStopped = False
        while True:
            logger.debug("Getting spotify properties")
            player_properties = dbus.Interface(
                spotify_bus,
                'org.freedesktop.DBus.Properties'
            )

            logger.debug("Getting metadata and status")
            metadata = player_properties.Get('org.mpris.MediaPlayer2.Player', 'Metadata')
            status = player_properties.Get('org.mpris.MediaPlayer2.Player', 'PlaybackStatus')
            logger.debug(f"Got metadata: {metadata} and status is {status}")

            # Handle main label
            artist = fix_string(metadata['xesam:artist'][0]) if metadata['xesam:artist'] else ''
            song = fix_string(metadata['xesam:title']) if metadata['xesam:title'] else ''
            album = fix_string(metadata['xesam:album']) if metadata['xesam:album'] else ''

            logger.debug(f"""Parsed below info:
            artist = {artist}
            song = {song}
            album = {album}""")

            if quiet and status == "Paused":
                print('')
            elif (not artist and not song and not album):
                print(colorize(no_player_label, status))
            else:
                if font:
                    artist = label_with_font.format(font=font, label=artist)
                    song = label_with_font.format(font=font, label=song)
                    album = label_with_font.format(font=font, label=album)

                temp_label = output.format(artist=artist, 
                                    song=song, 
                                    album=album)

                if status == "Playing":
                    hasStopped = False
                    if temp_label == original_label:
                        rolled_label = rolled_label[1:] + rolled_label[0]
                    else:
                        original_label = temp_label
                        rolled_label = temp_label + (" " * 5)
                    print(colorize(rolled_label, status))
                else:
                    if not hasStopped:
                        hasStopped = True
                        print(colorize(rolled_label, status))

            time.sleep(0.5) 
    except Exception as e:
        if isinstance(e, dbus.exceptions.DBusException):
            logger.debug(f"Dbus exception occurred. {e}")
            print(colorize(no_player_label, "NA"))
        else:
            logger.debug(f"{e}")

if __name__ == '__main__':
    while True:
        signal.signal(signal.SIGRTMIN + 1, signal.SIG_IGN)
        signal.signal(signal.SIGRTMIN + 2, signal.SIG_IGN)
        signal.signal(signal.SIGRTMIN + 3, signal.SIG_IGN)
        main()
        logger.debug("Crashed detected. Restarting...")
        time.sleep(1)
