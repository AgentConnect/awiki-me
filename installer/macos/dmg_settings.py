application_path = defines["application"]
background_path = defines["background"]

files = [(application_path, "AWikiMe.app")]
symlinks = {"Applications": "/Applications"}

format = "UDZO"
filesystem = "APFS"
background = background_path
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
window_rect = ((200, 120), (600, 380))
default_view = "icon-view"
show_icon_preview = False
include_icon_view_settings = True
arrange_by = None
label_pos = "bottom"
text_size = 13
icon_size = 112
icon_locations = {
    "AWikiMe.app": (155, 185),
    "Applications": (445, 185),
}
