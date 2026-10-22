Title: Adding Comments From Bluesky To This Blog
Published: 2026-10-22
Tags:
- meta
Lead: This blog can now pull in comments from bluesky, as well as the fediverse.
Announce: [bluesky, fedi]

Bluesky: https://bsky.app/profile/fastfinge.interfree.ca/post/3myhzcxznfk26
Fedi: https://fed.interfree.ca/notes/asna7jf306rs9bd0
---
In the modern world, blog comments are hard. If you run your own comment system, you get to deal with spammers, AI bots, and worse. You also have to deal with exploits on whatever comment system you use or any of the technology it depends on. That was the reason I built this blog as entirely static: once it's built, all the webserver does is serves HTML, JavaScript, and other files to your browser. No code at all is executed server-side.

However, that makes commenting for readers tricky. I could use a third-party comments system, of course. However, all of the ones that currently exist have privacy policies and run analytics that I won't expose my readers to. So the solution I've settled on since the start was to include comments as the reply's to a post on the fediverse (Mastodon or any other compatible software). Unfortunately, the UX for this is not ideal. First, you need to already have an account on some instance, somewhere. If you don't, you can't leave a comment at all. Second, you need to know how to track down and search for the exact post to reply to. I give you a link, but if you don't know what to do with it, there's no help for you. I could use a hashtag instead of a post, but then you get into problems with the way posts federate; my instance may not see the post from your hashtag at all, and thus you will miss the entire conversation.  Never the less, a good eighty percent of my audience is on Mastodon or other parts of the fediverse, so it's where most of my engagement comes from.  

I've long wanted to offer more options, though. Today, I've found a way to offer at least one more for some people: likes and comments from bluesky will now also show up on this blog. The bluesky post itself, as well as the standard.site publication, all live on my server, under my control. However, I am forced to depend on a public app view. After Twitter and Reddit discontinued there API's, I'm deeply, deeply reluctant to depend on an API I don't fully control myself. Bluesky is a VC funded company, and could inject ads, charge for API access, or just take the app view away entirely at any point.  But if they do, there are now at least two other app views available: blacksky and eurosky. I'm using the bluesky app view for the moment, because it's the fastest and most widely used. But if they ever break trust, I've made sure that moving to eurosky or blacksky is a one-line change. When I eventually do have to move, the data still belongs to me and lives on my PDS, and I should get access to most of the same comments. 

I've also added a link back to posts on LinkedIn, for the entries I think would be of interest to that audience. However, it's a manual process, as LinkedIn doesn't support allowing me to pull in comments, or posting via API without being an organization. I also don't want my reader's browsers contacting LinkedIn on every page load, so that's just a simple hyperlink, nothing more.

I'm still not entirely sure how I feel about these compromises. But I do need to find work, and that entails community building, self-promotion, and everything that comes with it.

By the way, if you're curious how exactly this blog works, or want to adapt it to your own purposes, the sourcecode is all on [github](https://github.com/fastfinge/stuff). It currently builds via github's ci/cd before deploying to my own server. But there's also a powershell script that can publish a new entry entirely locally, if I ever move away from GitHub, or need to stop using GitHub actions for whatever reason.