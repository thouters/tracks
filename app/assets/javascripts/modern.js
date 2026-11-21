/*
 * The "modern" theme's layout (body.modern-ui): the quick-add bar, the filter
 * chips, the sidebar as a drawer on phones and the "/" shortcut for search.
 * Does nothing with the other themes.
 */
var ModernUI = (function ($) {
  'use strict';

  var WEEKDAYS = {
    sun: 0, sunday: 0, zo: 0, zondag: 0,
    mon: 1, monday: 1, ma: 1, maandag: 1,
    tue: 2, tuesday: 2, di: 2, dinsdag: 2,
    wed: 3, wednesday: 3, wo: 3, woensdag: 3,
    thu: 4, thursday: 4, do: 4, donderdag: 4,
    fri: 5, friday: 5, vr: 5, vrijdag: 5,
    sat: 6, saturday: 6, za: 6, zaterdag: 6
  };

  function startOfToday() {
    var d = new Date();
    d.setHours(0, 0, 0, 0);
    return d;
  }

  function addDays(d, n) {
    var r = new Date(d.getTime());
    r.setDate(r.getDate() + n);
    return r;
  }

  /* today, tomorrow/morgen, a weekday (the next one), +3, 261120 (Tracks'
   * own yymmdd), 2026-11-20, or 20/11 */
  function parseDate(text) {
    var s = (text || '').toLowerCase().replace(/[.,]$/, '');
    var today = startOfToday();
    var m;
    if (s === 'today' || s === 'vandaag') return today;
    if (s === 'tomorrow' || s === 'tom' || s === 'morgen') return addDays(today, 1);
    if (WEEKDAYS.hasOwnProperty(s)) {
      var diff = (WEEKDAYS[s] - today.getDay() + 7) % 7;
      return addDays(today, diff === 0 ? 7 : diff);
    }
    if ((m = s.match(/^\+(\d{1,3})([dw]?)$/))) return addDays(today, parseInt(m[1], 10) * (m[2] === 'w' ? 7 : 1));
    if ((m = s.match(/^(\d{2})(\d{2})(\d{2})$/))) return new Date(2000 + +m[1], +m[2] - 1, +m[3]);
    if ((m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/))) return new Date(+m[1], +m[2] - 1, +m[3]);
    if ((m = s.match(/^(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?$/))) {
      var year = m[3] ? (m[3].length === 2 ? 2000 + +m[3] : +m[3]) : today.getFullYear();
      var d = new Date(year, +m[2] - 1, +m[1]);
      if (!m[3] && d < today) d.setFullYear(year + 1);
      return d;
    }
    return null;
  }

  /* The name from `names` that `wanted` means: exact, then with an @ in
   * front, then the first that starts with it, then one that contains it. */
  function matchName(wanted, names) {
    var w = wanted.toLowerCase();
    var lower = names.map(function (n) { return n.toLowerCase(); });
    var tries = [
      function (n) { return n === w; },
      function (n) { return n === '@' + w; },
      function (n) { return n.replace(/^@/, '').indexOf(w) === 0; },
      function (n) { return n.indexOf(w) !== -1; }
    ];
    for (var t = 0; t < tries.length; t++) {
      for (var i = 0; i < lower.length; i++) {
        if (tries[t](lower[i])) return names[i];
      }
    }
    return null;
  }

  /* Splits "Call plumber @phone ~House #urgent <fri *" into its parts, the
   * same markers as Tracks' e-mail gateway (RichMessageExtractor). A name
   * with spaces between quotes: ~"Garden shed", @"At home", or ~Garden_shed. */
  function parse(text, contexts, projects) {
    var out = { description: [], tags: [], context: null, project: null, due: null, showFrom: null, starred: false, errors: [] };
    var re = /([@~#]"[^"]+"|~\S+|@\S+|#\S+|[<>]\S+|(?:due|start):\S+|\*(?=\s|$)|\S+)/g;
    var m;
    while ((m = re.exec(text)) !== null) {
      var tok = m[1];
      var c = tok.charAt(0);
      if (c === '@' && tok.length > 1) {
        var wantedContext = unquote(tok.slice(1));
        out.context = matchName(wantedContext, contexts) || matchName(tok, contexts) || wantedContext;
      } else if (c === '~' && tok.length > 1) {
        var wantedProject = /^"/.test(tok.slice(1)) ? unquote(tok.slice(1)) : tok.slice(1).replace(/_/g, ' ');
        out.project = matchName(wantedProject, projects) || wantedProject;
      } else if (c === '#' && tok.length > 1) {
        out.tags.push(unquote(tok.slice(1)));
      } else if ((c === '<' || c === '>' || /^(due|start):/i.test(tok)) && tok.length > 1) {
        var isDue = c === '<' || /^due:/i.test(tok);
        var raw = tok.replace(/^([<>]|due:|start:)/i, '');
        var date = parseDate(raw);
        if (date) {
          if (isDue) out.due = date; else out.showFrom = date;
        } else {
          out.errors.push(tok);
          out.description.push(tok);
        }
      } else if (tok === '*') {
        out.starred = true;
      } else {
        out.description.push(tok);
      }
    }
    out.description = out.description.join(' ');
    return out;
  }

  function unquote(s) {
    return s.replace(/^"|"$/g, '');
  }

  function formatDate(d) {
    var format = (typeof dateFormat !== 'undefined' && dateFormat) ? dateFormat : 'dd/mm/yy';
    return $.datepicker.formatDate(format, d);
  }

  function setupQuickAdd() {
    var $form = $('#todo-form-new-action');
    var $quick = $('#mx-quickadd');
    if (!$form.length || !$quick.length) return;

    $quick.prop('hidden', false);
    $('#mx-fab').prop('hidden', false);
    $('body').addClass('mx-has-quickadd');

    var contexts = $quick.data('contexts') || [];
    var projects = $quick.data('projects') || [];
    var tags = $quick.data('tags') || [];
    var $input = $('#mx-quickadd-input');
    var suggest = setupSuggestions($quick, $input, { '@': contexts, '~': projects, '#': tags });

    $quick.on('submit', function (ev) {
      ev.preventDefault();
      if (suggest.isOpen()) return;
      var text = $.trim($input.val());
      if (!text) return;
      var p = parse(text, contexts, projects);
      if (!p.description) {
        $input.trigger('focus');
        return;
      }
      $form.find('#todo_description').val(p.description);
      if (p.context) $form.find('#todo_context_name').val(p.context);
      if (p.project) $form.find('#todo_project_name').val(p.project);
      // a star is the tag "starred" in Tracks, and saving the tags would drop it
      if (p.starred && p.tags.indexOf('starred') === -1) p.tags.push('starred');
      if (p.tags.length) {
        var $tags = $form.find('#tag_list');
        var existing = $.trim($tags.val());
        $tags.val((existing ? existing + ', ' : '') + p.tags.join(', '));
      }
      if (p.due) $form.find('#todo_due').val(formatDate(p.due));
      if (p.showFrom) $form.find('#todo_show_from').val(formatDate(p.showFrom));
      $form.find('#new_todo_starred').val(p.starred ? 'true' : 'false');

      // The form's own submit button: Tracks asks about a new context,
      // sends it with Ajax and adds the action to the page
      $form.find('button#todo_new_action_submit').trigger('click');
      $input.val('');
    });

    // Tracks puts errors in #error_status: show the whole form then
    $(document).ajaxComplete(function () {
      if ($.trim($form.find('#error_status').text()) !== '') showFullForm(true);
    });

    $('#mx-quickadd-more').on('click', function () {
      showFullForm(!$('body').hasClass('mx-show-form'));
    });

    $('#mx-fab').on('click', function () {
      $quick[0].scrollIntoView({ block: 'center' });
      $input.trigger('focus');
    });
  }

  /* --- completion of @context ~project #tag in the quick-add bar ------ */

  /* The marker and word being typed at the caret: "@ph" in "Call @ph|" */
  function tokenAtCaret(value, caret) {
    var before = value.slice(0, caret);
    var m = before.match(/(^|\s)([@~#])("[^"]*|[^\s"]*)$/);
    if (!m) return null;
    var quoted = m[3].charAt(0) === '"';
    var rest = value.slice(caret).match(quoted ? /^[^"\s]*"?/ : /^\S*/)[0];
    return {
      marker: m[2],
      query: quoted ? m[3].slice(1) : m[3],
      start: caret - m[2].length - m[3].length,
      end: caret + rest.length
    };
  }

  /* Names for the query: those starting with it, then those with a word
   * starting with it, then those containing it */
  function suggestionsFor(query, names, limit) {
    var q = query.toLowerCase().replace(/_/g, ' ');
    var ranked = [[], [], []];
    names.forEach(function (name) {
      var n = name.toLowerCase().replace(/^@/, '');
      if (n.indexOf(q) === 0) ranked[0].push(name);
      else if ((' ' + n).indexOf(' ' + q) !== -1) ranked[1].push(name);
      else if (n.indexOf(q) !== -1) ranked[2].push(name);
    });
    return ranked[0].concat(ranked[1], ranked[2]).slice(0, limit);
  }

  /* How a name goes into the bar, so that parse() reads it back */
  function insertText(marker, name) {
    if (marker === '@') name = name.replace(/^@/, '');
    return marker + (/[\s"]/.test(name) ? '"' + name.replace(/"/g, '') + '"' : name);
  }

  var measureCanvas;
  function textWidth(text, el) {
    measureCanvas = measureCanvas || document.createElement('canvas');
    var ctx = measureCanvas.getContext('2d');
    var cs = window.getComputedStyle(el);
    ctx.font = cs.fontStyle + ' ' + cs.fontWeight + ' ' + cs.fontSize + ' ' + cs.fontFamily;
    return ctx.measureText(text).width;
  }

  function setupSuggestions($quick, $input, namesByMarker) {
    var input = $input[0];
    var $list = $('<ul class="mx-suggest" id="mx-suggest" role="listbox" hidden></ul>').appendTo($quick);
    var token = null;
    var items = [];
    var active = 0;

    $input.attr({ role: 'combobox', 'aria-autocomplete': 'list', 'aria-controls': 'mx-suggest', 'aria-expanded': 'false' });

    function isOpen() { return !$list.prop('hidden'); }

    function close() {
      token = null;
      items = [];
      $list.prop('hidden', true).empty();
      $quick.removeClass('mx-suggesting');
      $input.attr('aria-expanded', 'false').removeAttr('aria-activedescendant');
    }

    function highlight(i) {
      active = (i + items.length) % items.length;
      var $opts = $list.children();
      $opts.attr('aria-selected', 'false');
      var $a = $opts.eq(active).attr('aria-selected', 'true');
      $input.attr('aria-activedescendant', $a.attr('id'));
      if ($a[0] && $a[0].scrollIntoView) $a[0].scrollIntoView({ block: 'nearest' });
    }

    function position() {
      var x = input.offsetLeft + textWidth(input.value.slice(0, token.start), input) - input.scrollLeft;
      var max = $quick.innerWidth() - $list.outerWidth() - 8;
      $list.css('left', Math.max(8, Math.min(x, max)) + 'px');
    }

    function update() {
      var t = input.selectionStart === input.selectionEnd ? tokenAtCaret(input.value, input.selectionStart) : null;
      var names = t ? (namesByMarker[t.marker] || []) : [];
      var found = t ? suggestionsFor(t.query, names, 8) : [];
      // nothing more to complete when the only match is what is typed
      if (found.length === 1 && insertText(t.marker, found[0]).toLowerCase() === input.value.slice(t.start, t.end).toLowerCase()) found = [];
      if (!found.length) { close(); return; }
      token = t;
      items = found;
      $list.empty();
      found.forEach(function (name, i) {
        $('<li role="option" class="mx-suggest-item"></li>')
          .attr('id', 'mx-suggest-' + i)
          .append($('<span class="mx-suggest-marker" aria-hidden="true"></span>').text(t.marker))
          .append($('<span class="mx-suggest-name"></span>').text(t.marker === '@' ? name.replace(/^@/, '') : name))
          .appendTo($list);
      });
      $list.prop('hidden', false);
      $quick.addClass('mx-suggesting');
      $input.attr('aria-expanded', 'true');
      position();
      highlight(0);
    }

    function accept(i) {
      var value = input.value;
      var text = insertText(token.marker, items[i]);
      var after = value.slice(token.end);
      if (!/^\s/.test(after)) after = ' ' + after;
      input.value = value.slice(0, token.start) + text + after;
      var caret = token.start + text.length + 1;
      input.setSelectionRange(caret, caret);
      close();
    }

    $input.on('input click', update);
    $input.on('keyup', function (ev) {
      if (ev.key === 'ArrowLeft' || ev.key === 'ArrowRight' || ev.key === 'Home' || ev.key === 'End') update();
    });
    $input.on('keydown', function (ev) {
      if (!isOpen()) return;
      switch (ev.key) {
        case 'ArrowDown': ev.preventDefault(); highlight(active + 1); break;
        case 'ArrowUp': ev.preventDefault(); highlight(active - 1); break;
        case 'Enter':
        case 'Tab': ev.preventDefault(); accept(active); break;
        case 'Escape': ev.preventDefault(); ev.stopPropagation(); close(); break;
      }
    });
    $input.on('blur', close);
    // mousedown, so the field keeps focus
    $list.on('mousedown', '.mx-suggest-item', function (ev) {
      ev.preventDefault();
      accept($(this).index());
    });

    return { isOpen: isOpen, close: close };
  }

  function showFullForm(show) {
    $('body').toggleClass('mx-show-form', show);
    $('#mx-quickadd-more').attr('aria-expanded', show ? 'true' : 'false');
    if (show) $('#todo_description').trigger('focus');
  }

  /* --- filter chips -------------------------------------------------- */
  var currentFilter = 'all';

  function matches(item, filter) {
    var $d = $(item).find('.description').first();
    switch (filter) {
      case 'due': return $d.find('.red, .amber').length > 0;
      case 'starred': return $(item).find('.todo_star.starred').length > 0;
      case 'noproject': return $d.find('a[href*="/projects/"]').length === 0;
      default: return true;
    }
  }

  function applyFilter() {
    var $box = $('#display_box');
    $box.find('.item-container').each(function () {
      $(this).toggleClass('mx-filtered-out', currentFilter !== 'all' && !matches(this, currentFilter));
    });
    $box.find('.container').each(function () {
      var $c = $(this);
      var items = $c.find('.item-container');
      var hidden = currentFilter !== 'all' && items.length > 0 && items.not('.mx-filtered-out').length === 0;
      $c.toggleClass('mx-empty-by-filter', hidden || (currentFilter !== 'all' && items.length === 0));
    });
  }

  function setupFilters() {
    var $filters = $('#mx-filters');
    if (!$('#display_box .item-container, #display_box .context').length) return;
    $filters.prop('hidden', false);
    $filters.on('click', '[data-mx-filter]', function () {
      currentFilter = $(this).data('mx-filter');
      $filters.find('[data-mx-filter]').attr('aria-pressed', 'false');
      $(this).attr('aria-pressed', 'true');
      applyFilter();
    });
    // actions added, moved or completed with Ajax
    $(document).ajaxComplete(function () {
      if (currentFilter !== 'all') applyFilter();
    });
  }

  /* --- sidebar as a drawer on phones ---------------------------------- */
  function setupDrawer() {
    $(document).on('click', '[data-mx-drawer]', function () {
      var open = $(this).data('mx-drawer') === 'open';
      $('body').toggleClass('mx-drawer-open', open);
      $('[data-mx-drawer="open"]').attr('aria-expanded', open ? 'true' : 'false');
      if (open) $('#mx-sidebar a:first').trigger('focus');
    });
    $(document).on('keydown', function (ev) {
      if (ev.key === 'Escape' && $('body').hasClass('mx-drawer-open')) {
        $('body').removeClass('mx-drawer-open');
        $('[data-mx-drawer="open"]').attr('aria-expanded', 'false').trigger('focus');
      }
    });
  }

  /* --- project board (projects#board) --------------------------------- */
  function setupBoard() {
    var $board = $('#mx-board');
    if (!$board.length) return;
    var url = $board.data('move-url');
    var touch = window.matchMedia && window.matchMedia('(hover: none)').matches;

    // the rank numbers (priority) and the column counts
    function refresh() {
      $board.find('.mx-cards').each(function () {
        var $list = $(this);
        var stage = $list.data('stage');
        var $cards = $list.children('.mx-card');
        $cards.each(function (i) {
          $(this).find('.mx-card-rank').text(stage === 'done' || stage === 'idea' ? '' : i + 1);
          $(this).find('.mx-card-stage').val(stage);
        });
        if (stage !== 'done') $list.closest('.mx-column').find('.mx-column-count').text($cards.length);
      });
    }

    function save($card) {
      var $list = $card.closest('.mx-cards');
      var order = $list.children('.mx-card').map(function () { return $(this).data('id'); }).get();
      $card.addClass('is-saving');
      refresh();
      $.ajax({
        url: url,
        type: 'POST',
        dataType: 'json',
        data: { id: $card.data('id'), stage: $list.data('stage'), order: order }
      }).done(function (res) {
        $card.removeClass('is-saving');
        $card.toggleClass('is-hidden', res.state === 'hidden' && res.stage !== 'idea');
      }).fail(function () {
        window.alert($board.data('error'));
        window.location.reload();
      });
    }

    var startList, startIndex;
    $board.find('.mx-cards').sortable({
      connectWith: '#mx-board .mx-cards',
      items: '> .mx-card',
      handle: touch ? '.mx-card-grip' : false,
      cancel: 'select, input, button',
      placeholder: 'mx-card-placeholder',
      forcePlaceholderSize: true,
      tolerance: 'pointer',
      distance: 4,
      start: function (ev, ui) {
        startList = ui.item.parent()[0];
        startIndex = ui.item.index();
      },
      stop: function (ev, ui) {
        if (ui.item.parent()[0] === startList && ui.item.index() === startIndex) return;
        save(ui.item);
      }
    });

    // the menu on each card: to the bottom of the chosen column
    $board.on('change', '.mx-card-stage', function () {
      var $card = $(this).closest('.mx-card');
      var $target = $board.find('.mx-cards[data-stage="' + $(this).val() + '"]');
      $card.appendTo($target);
      save($card);
      $card.removeClass('is-moved');
      void $card[0].offsetWidth;
      $card.addClass('is-moved');
      if (touch) $target.closest('.mx-column')[0].scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'start' });
    });

    // after adding a project, scroll to its column
    if (window.location.hash) {
      var col = document.getElementById(window.location.hash.slice(1));
      if (col) col.scrollIntoView({ block: 'nearest', inline: 'start' });
    }
    refresh();
  }

  /* "/" focuses search, "n" the quick-add bar, outside text fields */
  function setupShortcuts() {
    $(document).on('keydown', function (ev) {
      if (ev.ctrlKey || ev.metaKey || ev.altKey) return;
      var tag = (ev.target.tagName || '').toLowerCase();
      if (tag === 'input' || tag === 'textarea' || tag === 'select' || ev.target.isContentEditable) return;
      if (ev.key === '/') {
        ev.preventDefault();
        $('#mx-search-input').trigger('focus');
      } else if (ev.key === 'n' && !$('#mx-quickadd').prop('hidden')) {
        ev.preventDefault();
        $('#mx-quickadd-input').trigger('focus');
      }
    });
  }

  function init() {
    if (!$('body').hasClass('modern-ui')) return;
    setupQuickAdd();
    setupFilters();
    setupDrawer();
    setupShortcuts();
    setupBoard();
  }

  return { init: init, parse: parse, parseDate: parseDate, tokenAtCaret: tokenAtCaret, suggestionsFor: suggestionsFor, insertText: insertText };
})(jQuery);

jQuery(function () { ModernUI.init(); });
