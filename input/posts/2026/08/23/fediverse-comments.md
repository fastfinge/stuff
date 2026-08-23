Title: The Problems and Successes of Fediverse Comments on my blog
Published: 2026-08-23
Lead: I've been running fediverse as the commenting system on this blog for a while now. Here's how it's been going. #20260822_BlogCommentsViaHashtags 
Announce: fedi
InReplyTo: https://karl-voit.at/2026/08/22/Blog-Comments-via-Hashtags/
---
I was inspired to write this by a number of recent articles around the blogosphere (is that still a word people use?) on using the fediverse (or atproto) as a way to get comments on a static blog.  As someone who gets a lot of fediverse interaction, and has been doing this for a bit, the experience has been mixed. 

### The Problem of Hashtags ###

In his article on the subject, Karl Voit recommends using a unique hashtag to collect up comments under each article.  While he does mention many of the problems with this approach, he misses a major one that made the solution unworkable for me.  If you're on a smaller server, your server will not receive every post marked with a given hashtag. Each fediverse server only receives posts from users followed by users on that server, as well as any servers it shares an activitypub relay with. This means that, depending on the size of your server, and the size of the server the commenter is posting from, your article could end up missing a lot of comments intended for it. It also means that threads will often get broken, with not everyone involved in the conversation seeing all of it, and not all of it getting reproduced on your blog. Worse, commenters have no way to know what they're missing, or if the comment they wrote will ever show up for you or not.  Instead of promoting conversation, this promotes anxiety for everyone involved.

This problem could be solved by using something like [tags.pub](https://www.tags.pub) to follow every new hashtag for every article you publish. But that's another step to automate, I haven't tested the idea, and I don't know how wide the reach of tags.pub actually is.

### The Problem of Threads ###

However, that doesn't mean that threads are the perfect solution. Far from it! It does solve the above problems with hashtags, though. Because it's a thread, you will always be mentioned in any replies. This forces the reply to be delivered to you and your server, ensuring that it will always appear on your website. Also, most activitypub servers will backfill threads, so for the most part, everyone involved should get to see the entire thread.

But in return for solving those problems, threads introduce a massive UI problem. There is currently no way to link to a thread that will open in the users fediverse instance. You can open the thread on your own instance, or on some random large instance and hope, but that's it. The share.joinmastodon.org website and other similar services only work for Mastodon; there is no universal way to handle "open this thread on the user's fediverse instance". So users are just left with a thread URL, and hopefully the understanding that they need to put it into the search box of their instance, and that the instance will backfill and return the thread before they give up on the search entirely.  The result is that my articles tend to get a flood of comments when first posted, and people find the announcement post on fedi, followed by absolutely no comments at all. Instead, users create a new thread to comment, or give up and email me. Either way, those comments don't get on the website.

### The Lack of Generic Solutions ###

Every few weeks, someone tells me "Wow, that comment system is cool! How can I have one?" And I'm forced to tell them that the system is largely custom code, and can't be easily adapted to the particular framework they use. There is no fully generic system that is accessible and standards compliant, works with multiple types of fediverse servers, and isn't tightly coupled to one particular static framework. If you want to have fediverse comments on your blog, I just don't have an out of the box solution I can recommend. This also makes things confusing for users: some websites find comments by thread, some by hashtag, some by mentioning a unique activitypub actor for each article, and so on. When a website does accept fediverse comments, now users have to figure out how it works, because it's going to be slightly different each time.

### Why not bluesky/atproto? ###

The primary reason is that bluesky doesn't decentralize easily. If I want to include comments from bluesky on my blog, the only way is to call the centralized bluesky API to find the comments. I can't easily spin up my own API for the purpose. That means every user who visits an article I wrote pings a bluesky endpoint. If bluesky changes or discontinues the API, or goes down, comments are lost forever. Also, bluesky learns the IP of every user who reads any article on my website, and exactly what they read. And, to be frank, I don't trust bluesky.

### Why not a self-hosted commenting system? ###

I am a screen reader user, and about 85 to 90 percent of my audience also use screen readers. That rules out any kind of captcha, and means that almost all anti-spam solutions won't work for me. So on top of the complexity of running yet another database and web app for blog comments, I would just be flooded with endless spam.

### Conclusion ###

It turns out that, in the real world, comments from the fediverse kind of suck, actually. Either people can't find the thread to comment, or you use hashtags and comments go missing, or people get confused because the flow is different for every website that does it. But out of all of the awful solutions, they're the least awful solution I've found. So I'm not going to change any time soon. But I wouldn't call myself a happy customer, as it were.