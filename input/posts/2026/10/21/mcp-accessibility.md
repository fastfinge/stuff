Title: Investigating Model Context Protocol as an Accessibility Interface
published: 2026-10-21
Tags:
- articles
Lead: Can Model Context Protocol (MCP) have accessibility benefits for humans with disabilities, beyond just enabling AI? I built a tool we can use to find out!
Announce: fedi

Fedi: https://fed.interfree.ca/notes/aslujxe5222qmw2w
---

A good deal of digital ink has been spilled on the benefits (or lack thereof) that AI may bring to the field of accessibility.  Thus far, most of this discussion has been focused in two areas. First, will the need to make websites accessible to AI agents cause an uptick in semantic and well-structured HTML that is easier for AI to process? Second, will AI generated code be more or less accessible for users with disabilities?  However, nobody has yet investigated if the tools currently being created specifically for AI may be reused by screen readers and other non-LLM assistive technology.  As more and more websites intended for humans begin blocking agentic traffic, this problem becomes ever more pressing, and the idea of allowing assistive technology to use the same gateways provided for AI becomes ever more timely.

So, I set out to determine the possible benefit of these tools to non-AI using humans, starting with Model Context Protocol (MCP). If you've never heard the term, Model Context Protocol is a standardized way for websites and applications to define tools that AI agents can use.  Every MCP server must describe itself, all of the tools it provides, and all of the parameters every tool needs and what format they should be in. An MCP server can also indicate if a tool will take a destructive action or not, specify if parameters are required or optional, ask structured follow-up questions after a tool call, and then return the results in a structured way that AI can process.

That sounds a lot like what screen readers want, doesn't it? Screen reader users tend to want predictable interfaces, that reuse elements and UI patterns, and provide semantic data that's easy to navigate. So I wondered if it would be possible to connect to an MCP server, list all of the tools, and automatically build a user interface for every tool?  

That's why I built [humcp](https://github.com/fastfinge/humcp) (pronounced hume-cp). Humcp will allow you to add and configure MCP servers, list all of the tools they offer, and build accessible forms that will allow you to run any of them, showing you the results in a fully accessible interface.  At version 1.1, it even mostly works!

Unfortunately, though, the way that AI specifies information, and the way that humans specify and consume information, are quite different.  In order to demonstrate the problems, let's take a look at a couple sample MCP servers. If you want to follow along, grab a copy of humcp yourself!  You'll also need nodejs installed: in your windows terminal, run "winget install nodejs" if you don't have it already.

### Open-Meteo: Getting The Weather ###

To try out this server, once you have humcp running, go to the file menu on the menu bar, choose "import servers...", and enter:
``` json
{
  "mcpServers": {
    "open-meteo": {
      "command": "npx",
      "args": [
        "-y",
        "-p",
        "open-meteo-mcp-server",
        "open-meteo-mcp-server"
      ]
    }
  }
}
```

Now that we have the server added, we get a tree view listing all of it's tools.  Ah, Weather Forecast looks exactly like what I want! No more advertising heavy websites, inaccessible tables, or bulky apps, just to get the local weather. Let's press enter to run it.  We get a fully accessible form, no problem at all. But it wants a latitude and longitude.  Hmmm. This is something AI would probably have handy, from its perfect digital memory. I don't, though.  

But aha!  If I cursor up a little, I find a tool called geocoding.  It's an annoying extra step, but this will do exactly what I want. Enter to run it, fill out the accessible form, and there we go. The exact latitude and longitude for my city. Just copy that, and go back to the weather forecast tool, right? 

Well, not quite. If all you fill out here is the latitude and longitude, you don't actually get a forecast.  You have to expand the optional values, and select the variables you actually want, first. Once again, the process is entirely accessible.  But the UX is more suited for AI than for humans.  

### MLB ###

Another place where I frequently find data that's inaccessible or annoying to review is baseball scores. But there's an MCP server for that:
``` json
{
  "mcpServers": {
    "mlb": {
      "command": "npx",
      "args": [
        "@jerrysv/mlb-mcp-server",
        "bluejays"
      ]
    }
  }
}
```

To run it, just import the server from the file menu. Then you get another item in the tree view, listing the server and it's tools. Let's use get player stats, and find out about one of my favourite players.  Oh, hang on. We need a Player ID.

Once again, it's another step. First, we have to use find player. That gives us the player ID, and then we can use get player stats to learn more, and review the stats in a fully accessible interface.

### Conclusion ###

MCP easily provides enough information for an app to build fully accessible forms, and display results in a fully accessible interface.  In the case where a screen reader user needs to interact with a website or application that is otherwise inaccessible, this could be intensely useful.  I'm already using humcp daily myself, as I find requesting information and reading results much quicker than using a website, much easier than using a command line application, and often more efficient than asking a chatbot.  However, before MCP could be used universally as an accessibility tool, work needs to be done in the following areas:
* saving queries so they can be quickly repeated
* linking tools, to get an ID from one tool, and quickly paste it into a second one
* linking tools and entities, so that when a tool returns an ID or result, users can quickly pick other tools that can act on that result

However, I strongly feel that there's something here.  If you're interested in how AI currently uses tools, or you have an app or website that offers an MCP server but has otherwise poor accessibility, give Humcp a try!  It might not be the most friendly interface, but it will be a fully accessible one. I will continue developing the app, in order to work on the problems; this is an early 1.0 MVP, proving the concept. Now that I know it works, it can be refined quite a bit. But that refining process works best with you involved. So why not try it out? Do you, like me, find some tasks faster using humcp than using the website or interface intended for humans? What works for you, and what doesn't? [Download and try it out](https://github.com/fastfinge/humcp)! Your issues and pull requests are gladly welcome.