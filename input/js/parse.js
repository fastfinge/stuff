// based on https://github.com/pokiiio/hatena-blog-parser
function parse(rssUrl, rssList) {
    const request = new XMLHttpRequest();
    request.open('GET', rssUrl);
    request.addEventListener('load', (event) => {
      if (event.target.status !== 200) {
        const e = '<p>Error ' + event.target.status + ': ' + event.target.statusText + ' (sorry)</p>';
          document.getElementById(rssList).insertAdjacentHTML('beforeend', e);
          return;
      }

      const result = event.target.responseText;

      let data = [];

      result.split('<item>').forEach(element => {
        const postTitle = element.split('<title>')[1].split('</title>')[0];
        const postLink = element.split('<link>')[1].split('</link>')[0];

        var postDate = undefined; // item 0 (blog link/title) has no pubDate
        if (element.includes('<pubDate>')) {
          var postDate = element.split('<pubDate>')[1].split('</pubDate>')[0];
        };

        let post = {};
        post.postTitle = postTitle;
        post.postLink = postLink;
        post.postDate = postDate;
        data.push(post);
      });

      var d = document.getElementById(rssList);
      var i;
      for (i = 1; i < 6; i++) {
        var t = data[i].postDate; // MMM DD, YYYY
        var t = '<div class="date">' + t+ '</div>';
        var s = '<li>' + t + '<a target="_blank" href="' + data[i].postLink + '">' + data[i].postTitle + '</a></li>';
        d.insertAdjacentHTML('beforeend', s);
      }
    });
    request.send();
}