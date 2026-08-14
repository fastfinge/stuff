// Fragmentions: https://indieweb.org/fragmention
//
// A URL like /2026/05/20/some-post.html#the+exact+words+quoted takes the reader
// to the first place those words appear, without the post having had to put an
// id on that paragraph in advance. That means anyone can link to any sentence
// here, which is the point: a quote in someone else's post can point at the
// words it is quoting rather than at the top of the page.
//
// Only fires when the fragment does not match a real element id, so ordinary
// anchors keep working untouched. A page with JavaScript off loses the scroll
// and nothing else -- the URL still resolves to this page.
//
// Matching is confined to a single text node, so a phrase split across a link
// or an <em> will not be found. Widening that means rebuilding the text of the
// whole document and mapping offsets back onto nodes, which is a lot of moving
// parts for a rare case.
(function () {
  'use strict';

  var HIGHLIGHT_CLASS = 'fragmention-target';

  function phraseFromHash() {
    var hash = window.location.hash.slice(1);
    if (!hash) {
      return '';
    }
    // Fragmentions are written with + for spaces, the way a search query is.
    // decodeURIComponent first, so percent-encoded punctuation survives.
    try {
      hash = decodeURIComponent(hash);
    } catch (e) {
      // A malformed escape is not worth throwing over; use it as typed.
    }
    return hash.replace(/\+/g, ' ').trim();
  }

  function clearPrevious(root) {
    var previous = root.querySelectorAll('mark.' + HIGHLIGHT_CLASS);
    for (var i = 0; i < previous.length; i++) {
      var mark = previous[i];
      var parent = mark.parentNode;
      while (mark.firstChild) {
        parent.insertBefore(mark.firstChild, mark);
      }
      parent.removeChild(mark);
      // Undo the split the highlight caused, so a second search over the same
      // paragraph still sees one continuous run of text.
      parent.normalize();
    }
  }

  function findTextNode(root, phrase) {
    var needle = phrase.toLowerCase();
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (node) {
        // Skip anything that is not rendered prose.
        var tag = node.parentNode && node.parentNode.nodeName;
        if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT') {
          return NodeFilter.FILTER_REJECT;
        }
        return node.nodeValue.toLowerCase().indexOf(needle) === -1
          ? NodeFilter.FILTER_SKIP
          : NodeFilter.FILTER_ACCEPT;
      }
    });
    return walker.nextNode();
  }

  function highlight(node, phrase) {
    var start = node.nodeValue.toLowerCase().indexOf(phrase.toLowerCase());
    var after = node.splitText(start);
    after.splitText(phrase.length);

    var mark = document.createElement('mark');
    mark.className = HIGHLIGHT_CLASS;
    // Focusable but not in the tab order: focus is what actually moves a screen
    // reader's reading position to the phrase. Scrolling alone would leave a
    // screen reader user reading from the top of the page with no idea the
    // fragmention had done anything.
    mark.setAttribute('tabindex', '-1');
    node.parentNode.insertBefore(mark, after);
    mark.appendChild(after);
    return mark;
  }

  function go() {
    var phrase = phraseFromHash();
    var root = document.getElementById('content') || document.body;

    clearPrevious(root);

    if (!phrase) {
      return;
    }
    // A fragment that names a real element is an ordinary anchor. Leave it be.
    if (document.getElementById(window.location.hash.slice(1))) {
      return;
    }

    var node = findTextNode(root, phrase);
    if (!node) {
      return;
    }

    var mark = highlight(node, phrase);
    mark.focus();
    if (mark.scrollIntoView) {
      mark.scrollIntoView({ block: 'center' });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', go);
  } else {
    go();
  }
  window.addEventListener('hashchange', go);
})();
