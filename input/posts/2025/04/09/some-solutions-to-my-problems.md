Title: Some Solutions to My Problems
Lead: solutions to problems with imports and displaying shortcodes on micro.blog.
Published: 2025-04-08
Tags:
- blog meta
---
Okay, after a bit more fiddling, I think I've solved at least a few of my problems.

First, the books shortcode formatting is incorrect on the micro.blog plugin page. If you use the formatting from GitHub, it'll work.  This looks like a third party plugin, so I can't bash the service itself too hard for this one. Just some spaces that went missing somehow. As I've never used Hugo before, the mistake wasn't obvious to me.

Second, importing chrome bookmarks.  You need the chrome extension "bookmark export/import". You can get it from: [chromewebstore.google.com/detail/bo...](https://chromewebstore.google.com/detail/bookmark-importexport/gdhpeilfkeeajillmcncaelnppiakjhn)

To use it, do the following:
1. after opening the extension from the toolbar, select the advanced option, and change the format to CSV.
2. press settings, and make sure icon metadata is off, last modified times are off, hide root folder is off, and hide parent folders are off.
3.  After exporting the CSV file, open it in notepad, and change the first line to the following (including quotes): "Title","URL","Folder","Timestamp"

That should work!  
