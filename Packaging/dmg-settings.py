from pathlib import Path
import subprocess
from mac_alias import Bookmark


class NativeBookmark:
    def __init__(self, data):
        self.data = data

    def to_bytes(self):
        return self.data


def background_bookmark(path):
    return NativeBookmark(subprocess.check_output([defines["bookmark_encoder"], path]))


# The portable Python encoder's background bookmarks fail to resolve on the
# target macOS. Keep the DS_Store writer, but encode this reference natively.
Bookmark.for_file = staticmethod(background_bookmark)

# Only packaging metadata. The application has no Python dependency.
application = Path(defines["app"])
files = [(str(application), "PluginShelf.app")]
symlinks = {"应用程序": "/Applications"}
# Finder already presents application bundles without the extension. Setting
# its hidden-extension flag would add FinderInfo to the signed app bundle.
hide_extensions = []
icon = str(application / "Contents/Resources/AppIcon.icns")
background = defines["background"]
format = "UDZO"
filesystem = "HFS+"
# Leave room for Finder's optional tab, path and status bars. Current macOS may
# retain those user preferences even with the folder-specific flags below.
window_rect = ((180, 140), (640, 480))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
include_list_view_settings = False
arrange_by = None
grid_offset = (0, 0)
grid_spacing = 100
scroll_position = (0, 0)
label_pos = "bottom"
text_size = 14
icon_size = 96
icon_locations = {"PluginShelf.app": (166, 180), "应用程序": (474, 180)}


def create_hook(mount_point, options):
    # Validate the copied application after all Finder file flags are applied.
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict",
                    str(Path(mount_point) / "PluginShelf.app")], check=True)
