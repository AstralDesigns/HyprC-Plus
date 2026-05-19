So in preparation of the future control center design we should split the bar editing into sub-tabs like in hyprpanel and each sub-tab will have sub-sections. Each tab should have specific edit options specific to the specific tab's targets and seprate from the other tabs.
BAR (Dropdown tabs below) :
1. Genral: for shared options like bar height, islandSpacing and module rdaius. far-left and far-right spacing between the bar and whichever modules are close to the bar left and right edges based on the barBg.left and barBg.right anchors in bar mode.
Appended modules where modules can be added indiviudally/removed from the bar or added or removed from the group  i.e not included in the groups modules and the appended in the bar modules individually.
```
In the future control center it will look something like
|left:["module1", "module2",...]    |Available modules not included:
|				    |"module 1", "module2",...
|center:["module1", "module2",...]  | 
|				    |
|right:["module1", "module2",...]   |
And prefereably they cand be dragged and droppd
```
Also shared glyph icon size for group icons, individual icons, media player icon(not play/pause icon after the media thumbnail), and icons just before the date & time modules text (if possible also target the weather weather code icon in the weather module while the numerical weather value gets text size).
Separate battery icon radial size and when charging a floating lightning glyph should appear centered inside the battery radial which scales based on radial size.
On the note of text size, target date&time, battery and weather degree value text.
2. Icons: set workspace icons to be used in glyph icons mode and another entry for dots mode and another entry for the workspace seperators plus their other editable options, distro/control-center icon, all other individual/standalone modules or group icons (excluding the notifications, clock, power-profiles, battery-radial icons and power/start button icons can be edited) can also be edited.
2. Workspaces: all editable options like glyph size, icon spacing (let 0 be true zero), padding, selection between glyph icons or numbered format.
3. Media: with all editable variables spacing (let 0 be true zero), padding, play/pause icon size, media info text size, media thumbnail size and whether to enebale or disable it.
4. Cava: clickable buttons to set the active cava ascii style like our current dots style in, or bars, larger dots full/hollow/mix etc. (as options many as you can add), cava color (single or gradient - where matugen colors are listed in an collapsable menu for both the gradient color and single color options), cava width which extends the cava modules on both sides and the cava ascii in them.(When being trnaparent due to no media its modules shouldn't collapse). Also aside from the width setting can the Cava qml have a height and psacing flagadded which will also be added to the conrol center
5. Background: backhground colors with two single/gradient options similar to the cava forground but now for the background color of workspace module, grouped modules, ungrouped modules, media, cava, active-window ... as well as opacity scales/sliders+small-value-entry-box for each of those

Layout & requirements:
1. The control center should be centered in the screen taking up about 4-fifthe of te screen height and about 2/3 of the width.
2. Somewhat windows style design with user info on the top left corner of the sidebar and the control center options on the right side after the sidebar.
3. The sidebar should have the main button options then for the extesnive bar optiosn, they should be split into sub-tabs i.e as the main button are moved from the current horizontal layout to the vertical layout the bar subsection sub-tabs should be moved to the right side of the screen based on the Quickshell bar Config.qml and this Bar-plan.md.
4 The user info section should have a user icon selection where when the image circle is clicked the user can pick an image to be transformed through imagemagick into a user icon and the same image will be copied to ~/.config/hyprcandy/user-icon.png so the start menu can use the same image for the startmenu user icon the same way the legacy GJS candy-utils control center did.
5. Complete the options integration from the candy-utils settings to the qs control center mainly for Hyprland, Themes, Dock, Menus and SDDM targeting the same original variables along with the waybar replacement by qs bar and the removal of swaync.

Align everything in the Config.qml first before we start on the 

Extra features requests:
- add a tri-islands mode to the bar where the left, center and right modules will be split into 3 unified islands which will be just before the full islands mode where it will be like three bars being edited in the same mammaner like for the far left/right spacing for the three bars now the way it's done in the full bar mode, shared border height but if possible so basically just using the settings for the full bar mode excpet from the tri-split since the edit options for the internal modules won't change.
- the clock icon can use the nf-md-clock_time icons with the filled versions for daytime and the outline versions for night time which based on each hour and between day and night
-  the system-update module is usually breifly hidden during scans, instead the module should a cycling loading dots radial before it the indicator icon for being up-to date or having available updates show up
- style the tray popovers to be OnSecondary background color with Primary color text and 0.8 alpha Primary color seperators with 20px radius and should show up right belo the system tray and 3 px after the bar border
Missing+fix-requets:
- actually fix the cava display through quickshell's documentation if quickshell has native cava support or a custom cava manager as a last resort
- fix active window indicator (it also shouldn't collapse when empty - since a user can choose to set its background alpha to 0 so when empty it just appears to have collapsed or keep a higher background alpha but the module will be empty when the program lacks an icon)
- on the workspaces module please add dispatch to clicked workspace and if there are sperators you can add turning them on or off between then workpsace icons and if they are on they can have glyph icons entry option for the seperators as well in the icons section with size, padding and spacing options.
- all editable icons should be included from Config.wml including seperator icons with their editable variables and workspace icons in the thre modes.
- the bar should have an extra tri-islands mode to the bar where the left, center and right modules will be split into 3 unified islands which will be just before the full islands mode where it will be like three bars being edited in the same mammaner like for the far left/right spacing for the three bars now the way it's done in the full bar mode, shared border height but if possible so basically just using the settings for the full bar mode excpet from the tri-split since the edit options for the internal modules won't change.
- the clock icon can use the nf-md-clock_time icons with the filled versions for daytime and the outline versions for night time which based on each hour and between day and night.
- try  fixing the active -window icon because icons are clearly being generated in the workpsace overview and notfications modules.
