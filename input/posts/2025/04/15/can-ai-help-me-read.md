Title: Can AI help me read scans of golden-age science fiction magazines?
Lead: I try multiple AI tools to attempt to get an accurately transcribed and formatted version of the Astounding Magazine of Science Fiction and Fantasy from 1955. This stream of consciousness article documents how it went.
Published: 2025-04-15
Tags:
- articles
Image: img/66debd1fc55022d58fc19ea83debf6ae.png
Fedi: https://fed.interfree.ca/notes/a6mw9eplvx9pyea1
---
I've always loved golden-age pulp science fiction.  Unfortunately, the scans of magazines like astounding are generally of poor enough quality that standard OCR struggles with them.  

So I thought: what better use for AI than reading public domain science fiction?  I downloaded a [random issue of Astounding Science Fiction and Fantasy from the internet archive](https://archive.org/details/sim_astounding-science-fiction_1955-03_55_1), this one printed in 1955. I started by grabbing the PDF.  

First, I tried uploading it to Chat GPT with the following prompt: "I love reading golden age science fiction from the public domain. Unfortunately, the magazine scans are generally not accessible, and the OCR doesn't do a good job. Could you produce an accessible version of this PDF?"

It responded "I’ve converted the March 1955 issue of Astounding Science Fiction into an accessible plain text version. You can download it using the link below". Unfortunately, the .txt file it offered me consisted of...74,498 blank lines. When I informed it of this fact, it tried to just run an OCR tool on the PDF. But that produced identical results to the OCR done by archive.org. In both cases, the first page reads like this: "March 1955 - 35 Cents ‘ Astoundinc
BCIENCE FICTIOw | Sense From Thnucht Nivide .. ...... —_—".  Not really readable!  

So I tried Google Gemini 2.5. It was more promising! It began outputting perfect versions of each page, with everything nicely marked for screen readers.  Unfortunately, it got to page 12 and timed out. Also, it sighted the source of every paragraph with a footnote that lead back to the PDF. Yes, Gemini, I know that the text came from the PDF I just uploaded to you! This is also annoying to read with a screen reader. It's output looks like this:
> Astounding SCIENCE FICTION
> Volume LV, Number 1 - March 1955
> (Cover)
> • Image: Sense From Thought Divide
> • Price: 35 Cents
> (Page 2 - Advertisement)
> • NICK CARTER MASTER DETECTIVE
> • Suspense-packed case histories with America's top fictional sleuth.
> • SUNDAYS 4:30 pm EST
> • MUTUAL Broadcasting System MBS

So I figured: the timeout is probably because I'm using the official gemini interface. What if I try BasiliskLLM? Unfortunately, it only supports images, not pdfs. So I thought I'd download the raw images from the Internet Archive.  Unfortunately...they're in JPEG2000, and it doesn't support that image format!  

Deep breaths.  Okay! How about Google Notebook? It might have longer timeouts, right?  I gave it the PDF file and the prompt, and it did the same thing Chat GPT did, and just performed basic OCR.  So I asked: "There are lots of OCR errors. Could you correct them based on the images in the PDF?" It gave me output like this:
> Yes, I can certainly help you with correcting the OCR errors based on the images in the PDF. Here are some of the corrections I've identified, presented by the source page number:
> •
> Page 1 :
> ◦
> "Sense Fram Thauoht Nivide .." should likely be "Sense From Thought Divide .."
> ◦
> "mee stounding" should likely be "the astounding"
> •
> Page 2 :
> ◦
> "ety he" should likely be "at the"
> ◦
> "(LEASE PRINT) ro Mail" should likely be "(PLEASE PRINT) to Mail"

Even deeper breaths! Not useful. Okay, but we're getting closer. How about if I ask "Please provide the fully corrected text." It replies, "NotebookLM can’t answer this question. Try rephrasing it, or ask a different question."  I might pass out if I take anymore deep breaths.

Right, but that gives me something else to try. What about using Chat GPT canvas, changing the model to 4o, and giving a more specific prompt: 
"I love reading golden age science fiction from the public domain. Unfortunately, the magazine scans are generally not accessible, and the OCR doesn't do a good job. I need the text from this PDF accurately transcribed, correctly formatted , with all the text, and descriptions of any artwork."

Close! Unfortunately, that causes it to describe the artwork and summarize the text.  I fiddled with the prompt, but it would always start summarizing after a few pages.  

Okay, what if we don't give it the PDF? Can it handle images? Let's modify the prompt a bit, and upload a zip file of an image of each page: "I love reading golden age science fiction from the public domain. Unfortunately, magazine scans are not accessible, and OCR doesn't do a good job. I need this magazine accurately transcribed, correctly formatted , with all the text, and descriptions of any artwork."

Once I switched to using the 4o reasoning model, that did the trick. It did the first eight pages, then asked me if I wanted any changes, or if it should continue.  

Here's the admittedly impressive sample output it gave me: <a href="https://stuff.interfree.ca/uploads/2025/astounding-1955-03-story1.html">astounding-1955-03-story1.html</a>

In conclusion, AI can almost, but not quite do this. The problems I had were more a matter of tooling.  If I was serious about reading these magazines regularly, for more than just entertainment value, my best bet would be to write a program to:
* feed AI an image of each page, and instruct it to transcribe it into markdown
* check that the result is an expected length and contains markdown formatting
* compare the AI page with standard inaccurate OCR, to sanity check that some of the expected text is present
* add each page to the final markdown file, and convert it to html

Getting an AI to write the code to do this is, however, left as a project for the reader.
