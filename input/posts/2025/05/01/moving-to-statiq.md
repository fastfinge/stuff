Title: Moved The Blog to Static
Published: 2025-05-01
Lead: My adventures in continuing to fiddle with my blog.
Tags:
- blog meta
Fedi: https://fed.interfree.ca/notes/a79415kevtrb3c08
---
Yes, that's right! I've become one of those tiresome middle-aged men who is constantly fiddling with their blog, and insists on telling you about it.  I'm sorry. 

After a few weaks of [micro.blog](https://www.micro.blog), it turns out that just wasn't the place for me.  While it was accessible, too many of the features didn't work well with my setup (like crossposting), or couldn't quite be made to do what I want. Also, I find that the way Hugo works absolutely destroys my brain.  So I needed something better.

My requirements were:
* not in the US
* easy for me to understand
* accessible
* keeps all existing urls in tact

I eventually settled on [statiq](https://www.statiq.dev). I understand the dotnet ecosystem, so it's easy for me to write markdown (or html) and deploy with powershell.  The disadvantage, of course, is I don't get an app that allows me to post remotely, or an easy way to offer an email newsletter. At some point I'll build these things when I want them badly enough.  

Also, if you have JavaScript, you now see fediverse replies under every post.  That's where most of my engagement comes from, and for whatever reason, the micro.blog comment system wasn't allowing folks to log in anyway.  Now the site feels a bit more alive.  If you don't have JavaScript, you still get a link to the original comment so you can load the thread in your client of choice. The only thing that won't work at all without JavaScript is the search; I don't want to host my own, and linking out to Google is no solution.

In the future, my plan is to automate Fediverse crossposting by adding it to the deploy pipeline. Then I can just post with a simple web script.  But manual posting will be fine for a bit until I decide if this is what I intend to stick with (I hope so!)