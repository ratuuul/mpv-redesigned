/* ==========================================================================
   mpv-redesigned - site behaviour
   --------------------------------------------------------------------------
   The page is built so that it still reads correctly with every CDN blocked:
   the content that comes from config-data.js is rendered by this file with
   plain DOM calls, Ant Design only ever enhances what is already on screen,
   and Alpine only drives the drawer, the tabs and the search state.

   Boot order:
     1. this file runs (deferred, so the DOM is parsed)
     2. Alpine starts and registers its components
     3. DOMContentLoaded fires, this file renders the content and mounts
        Ant Design and the WebGL background
   ========================================================================== */
(function (global) {
  'use strict';

  var DATA = global.MPVR || {
    stats: [],
    features: [],
    keybindings: [],
    configTree: [],
    installFlags: [],
    faq: []
  };

  /* ---------------------------------------------------------- utilities -- */

  function $(selector, root) {
    return (root || document).querySelector(selector);
  }

  function $$(selector, root) {
    return Array.prototype.slice.call((root || document).querySelectorAll(selector));
  }

  function escapeHtml(value) {
    return String(value === undefined || value === null ? '' : value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function reducedMotion() {
    return !!(global.matchMedia && global.matchMedia('(prefers-reduced-motion: reduce)').matches);
  }

  function navHeight() {
    var nav = $('.nav-shell');
    return nav ? nav.getBoundingClientRect().height : 72;
  }

  /* -------------------------------------------------- key binding store -- */

  var BindingStore = {
    query: '',
    sortKey: 'keys',
    sortDir: 'asc',
    subscribers: [],

    subscribe: function (fn) {
      this.subscribers.push(fn);
      fn(this);
    },

    emit: function () {
      for (var i = 0; i < this.subscribers.length; i += 1) {
        try {
          this.subscribers[i](this);
        } catch (err) {
          /* a broken subscriber must never take the page down */
        }
      }
    },

    setQuery: function (value) {
      this.query = value || '';
      this.emit();
    },

    toggleSort: function (key) {
      if (this.sortKey === key) {
        this.sortDir = this.sortDir === 'asc' ? 'desc' : 'asc';
      } else {
        this.sortKey = key;
        this.sortDir = 'asc';
      }
      this.emit();
    },

    filtered: function () {
      var needle = this.query.trim().toLowerCase();
      if (!needle) return DATA.keybindings.slice();
      return DATA.keybindings.filter(function (row) {
        return (
          row.keys.toLowerCase().indexOf(needle) !== -1 ||
          row.action.toLowerCase().indexOf(needle) !== -1 ||
          row.group.toLowerCase().indexOf(needle) !== -1 ||
          row.source.toLowerCase().indexOf(needle) !== -1
        );
      });
    },

    sorted: function () {
      var key = this.sortKey;
      var dir = this.sortDir === 'asc' ? 1 : -1;
      return this.filtered().slice().sort(function (a, b) {
        return String(a[key]).localeCompare(String(b[key])) * dir;
      });
    }
  };

  /* ------------------------------------------------------- content render -- */

  function renderFeatures() {
    var grid = $('#feature-grid');
    if (!grid || !DATA.features.length) return;

    var html = DATA.features.map(function (feature, index) {
      var number = ('0' + (index + 1)).slice(-2);
      var delay = (index % 4) * 50;
      return (
        '<article class="index-row reveal" style="--reveal-delay:' + delay + 'ms">' +
          '<span class="index-num">' + number + '</span>' +
          '<div>' +
            '<h3 class="index-title">' + escapeHtml(feature.title) + '</h3>' +
            '<p class="index-body">' + escapeHtml(feature.body) + '</p>' +
            '<p class="index-tag">' + escapeHtml(feature.tag) + '</p>' +
          '</div>' +
        '</article>'
      );
    }).join('');

    grid.innerHTML = html;
  }

  function renderConfigTree() {
    var host = $('#config-tree');
    if (!host || !DATA.configTree.length) return;

    var html = DATA.configTree.map(function (row, index) {
      return (
        '<div class="code-line reveal" style="--reveal-delay:' + (index % 6) * 40 + 'ms">' +
          '<span class="code-tree">' + escapeHtml(row.tree) + '</span>' +
          '<span class="code-note">' + escapeHtml(row.note) + '</span>' +
        '</div>'
      );
    }).join('');

    host.innerHTML = html;
  }

  function renderInstallFlags() {
    var body = $('#install-flags-body');
    if (!body || !DATA.installFlags.length) return;

    body.innerHTML = DATA.installFlags.map(function (row, index) {
      return (
        '<tr class="install-row">' +
          '<td class="py-3 pr-4"><code class="mono text-[0.78rem] text-ink">' + escapeHtml(row.flag) + '</code></td>' +
          '<td class="py-3 pr-4"><code class="mono text-[0.74rem] text-signal">' + escapeHtml(row.switch) + '</code></td>' +
          '<td class="py-3 text-sm leading-relaxed text-ink-dim">' + escapeHtml(row.body) + '</td>' +
        '</tr>'
      );
    }).join('');
  }

  function renderStatsFallback() {
    var host = $('#stats-fallback');
    if (!host || !DATA.stats.length) return;

    host.innerHTML = DATA.stats.map(function (stat) {
      return (
        '<div class="stat">' +
          '<p class="kicker">' + escapeHtml(stat.title) + '</p>' +
          '<p class="stat-value">' + escapeHtml(stat.value) + '</p>' +
          '<p class="stat-detail">' + escapeHtml(stat.detail) + '</p>' +
        '</div>'
      );
    }).join('');
  }

  function renderFaqFallback() {
    var host = $('#faq-fallback');
    if (!host || !DATA.faq.length) return;

    host.innerHTML = DATA.faq.map(function (item) {
      return (
        '<details class="qa">' +
          '<summary>' +
            '<span>' + escapeHtml(item.q) + '</span>' +
            '<span class="plus" aria-hidden="true">+</span>' +
          '</summary>' +
          '<p class="answer">' + escapeHtml(item.a) + '</p>' +
        '</details>'
      );
    }).join('');
  }

  function renderBindingsPlain() {
    var body = $('#bindings-plain-body');
    if (!body) return;

    var rows = BindingStore.sorted();
    body.innerHTML = rows.map(function (row) {
      return (
        '<tr class="binding-row">' +
          '<td class="py-3 pr-4"><kbd>' + escapeHtml(row.keys) + '</kbd></td>' +
          '<td class="py-3 pr-4 text-sm leading-relaxed text-ink-dim">' + escapeHtml(row.action) + '</td>' +
          '<td class="py-3 pr-4 text-xs text-ink-faint">' + escapeHtml(row.group) + '</td>' +
          '<td class="mono py-3 text-xs text-ink-faint">' + escapeHtml(row.source) + '</td>' +
        '</tr>'
      );
    }).join('');

    var empty = $('#bindings-empty');
    if (empty) empty.classList.toggle('hidden', rows.length !== 0);
  }

  /* ------------------------------------------------------ ant design mount -- */

  function antTheme() {
    return {
      algorithm: global.antd.theme.defaultAlgorithm,
      token: {
        colorPrimary: '#bc3a1e',
        colorInfo: '#bc3a1e',
        colorSuccess: '#bc3a1e',
        colorBgBase: '#e7e8e4',
        colorBgContainer: 'transparent',
        colorBgElevated: '#dfe0da',
        colorBorder: '#c3c4bd',
        colorBorderSecondary: '#d3d4ce',
        borderRadius: 2,
        fontFamily: "'Archivo', system-ui, sans-serif",
        fontSize: 15
      },
      components: {
        Table: {
          headerBg: 'transparent',
          headerColor: '#5a5e63',
          rowHoverBg: 'rgba(22, 23, 26, 0.04)',
          borderColor: '#d3d4ce'
        },
        Collapse: {
          headerBg: 'transparent',
          contentBg: 'transparent'
        }
      }
    };
  }

  function showOnly(node, visible) {
    if (!node) return;
    node.classList.toggle('hidden', !visible);
  }

  /* The React commit lands on its own schedule, so the swap to the enhanced
     layer is retried a few times before the plain layer is put away. */
  function swapWhenReady(host, fallback) {
    [80, 240, 600, 1400, 3000].forEach(function (delay) {
      global.setTimeout(function () {
        if (!host || !host.childElementCount) return;
        showOnly(host, true);
        showOnly(fallback, false);
      }, delay);
    });
  }

  var antdMounted = { stats: false, bindings: false, faq: false };

  function mountStatsAnt() {
    if (antdMounted.stats) return true;
    var a = global.antd;
    var R = global.React;
    var RD = global.ReactDOM;
    if (!a || !R || !RD || !RD.createRoot) return false;

    var host = $('#stats-antd');
    if (!host) return false;

    try {
      var root = RD.createRoot(host);
      var children = DATA.stats.map(function (stat) {
        return R.createElement(
          'div',
          { key: stat.title, className: 'stat' },
          R.createElement(a.Statistic, {
            title: stat.title,
            value: stat.value,
            valueStyle: { fontWeight: 400 }
          }),
          R.createElement(
            'p',
            { className: 'stat-detail' },
            stat.detail
          )
        );
      });

      root.render(
        R.createElement(
          a.ConfigProvider,
          { theme: antTheme() },
          R.createElement('div', { className: 'stat-strip antd-surface' }, children)
        )
      );

      antdMounted.stats = true;
      swapWhenReady(host, $('#stats-fallback'));
      return true;
    } catch (err) {
      return false;
    }
  }

  function mountBindingsAnt() {
    if (antdMounted.bindings) return true;
    var a = global.antd;
    var R = global.React;
    var RD = global.ReactDOM;
    if (!a || !R || !RD || !RD.createRoot) {
      showOnly($('#bindings-plain'), true);
      return false;
    }

    var host = $('#bindings-antd');
    if (!host) {
      showOnly($('#bindings-plain'), true);
      return false;
    }

    function render() {
      var rows = BindingStore.filtered();
      var columns = [
        {
          title: 'Key',
          dataIndex: 'keys',
          key: 'keys',
          width: 200,
          sorter: function (a1, b1) { return a1.keys.localeCompare(b1.keys); },
          render: function (value) { return R.createElement('kbd', null, value); }
        },
        {
          title: 'Action',
          dataIndex: 'action',
          key: 'action',
          sorter: function (a1, b1) { return a1.action.localeCompare(b1.action); },
          render: function (value) { return R.createElement('span', { className: 'text-ink-dim' }, value); }
        },
        {
          title: 'Group',
          dataIndex: 'group',
          key: 'group',
          width: 150,
          sorter: function (a1, b1) { return a1.group.localeCompare(b1.group); },
          render: function (value) { return R.createElement('span', { className: 'text-ink-faint' }, value); }
        },
        {
          title: 'Source',
          dataIndex: 'source',
          key: 'source',
          width: 130,
          sorter: function (a1, b1) { return a1.source.localeCompare(b1.source); },
          render: function (value) { return R.createElement('span', { className: 'mono text-ink-faint' }, value); }
        }
      ];

      var table = R.createElement(a.Table, {
        rowKey: 'id',
        dataSource: rows,
        columns: columns,
        size: 'small',
        scroll: { x: 760 },
        pagination: false,
        onChange: function (pagination, filters, sorter) {
          if (!sorter || !sorter.columnKey || !sorter.order) return;
          BindingStore.sortKey = sorter.columnKey;
          BindingStore.sortDir = sorter.order === 'ascend' ? 'asc' : 'desc';
          BindingStore.emit();
        }
      });

      return R.createElement(
        a.ConfigProvider,
        { theme: antTheme() },
        R.createElement('div', { className: 'antd-surface' }, table)
      );
    }

    try {
      var root = RD.createRoot(host);
      BindingStore.subscribe(function () {
        root.render(render());
      });
      antdMounted.bindings = true;
      swapWhenReady(host, $('#bindings-plain'));
      return true;
    } catch (err) {
      showOnly($('#bindings-plain'), true);
      return false;
    }
  }

  function mountFaqAnt() {
    if (antdMounted.faq) return true;
    var a = global.antd;
    var R = global.React;
    var RD = global.ReactDOM;
    if (!a || !R || !RD || !RD.createRoot) return false;

    var host = $('#faq-antd');
    if (!host) return false;

    try {
      var root = RD.createRoot(host);
      var items = DATA.faq.map(function (item, index) {
        return {
          key: String(index),
          label: item.q,
          children: R.createElement('p', null, item.a)
        };
      });

      root.render(
        R.createElement(
          a.ConfigProvider,
          { theme: antTheme() },
          R.createElement(
            'div',
            { className: 'antd-surface' },
            R.createElement(a.Collapse, { items: items, ghost: true, expandIconPosition: 'end' })
          )
        )
      );

      antdMounted.faq = true;
      swapWhenReady(host, $('#faq-fallback'));
      return true;
    } catch (err) {
      return false;
    }
  }

  /* ------------------------------------------------------------- reveal -- */

  function initReveal() {
    var items = $$('.reveal');
    if (!items.length) return;

    if (!global.IntersectionObserver || reducedMotion()) {
      items.forEach(function (item) { item.classList.add('is-visible'); });
      return;
    }

    var observer = new global.IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        });
      },
      { rootMargin: '0px 0px -8% 0px', threshold: 0.06 }
    );

    items.forEach(function (item) { observer.observe(item); });
  }

  /* ---------------------------------------------------------- navigation -- */

  /* The document is the file and the scroll is the playhead. The bar at the
     top of the window is the scrubber, and the readout in the navigation bar
     is the timecode of the position you are at. */
  var REEL_FRAMES = 12 * 60 * 60 * 24;

  function formatTimecode(frames) {
    var total = Math.max(0, Math.floor(frames));
    var f = total % 24;
    var s = Math.floor(total / 24) % 60;
    var m = Math.floor(total / (24 * 60)) % 60;
    var h = Math.floor(total / (24 * 60 * 60));
    function pad(n) { return (n < 10 ? '0' : '') + n; }
    return pad(h) + ':' + pad(m) + ':' + pad(s) + ':' + pad(f);
  }

  function initPlayhead() {
    var fill = $('#playhead-fill');
    var readout = $('#tc-readout');
    if (!fill && !readout) return;

    function update() {
      var doc = document.documentElement;
      var max = (doc.scrollHeight - (global.innerHeight || 0)) || 1;
      var y = global.pageYOffset || doc.scrollTop || 0;
      var ratio = Math.min(1, Math.max(0, y / max));
      if (fill) fill.style.transform = 'scaleX(' + ratio.toFixed(4) + ')';
      if (readout) readout.textContent = formatTimecode(ratio * REEL_FRAMES);
    }

    update();
    global.addEventListener('scroll', update, { passive: true });
    global.addEventListener('resize', update);
  }

  function initNav() {
    var shell = $('.nav-shell');
    var backToTop = $('#back-to-top');

    function onScroll() {
      var y = global.pageYOffset || document.documentElement.scrollTop || 0;
      if (shell) shell.classList.toggle('is-stuck', y > 24);
      if (backToTop) backToTop.classList.toggle('is-visible', y > 620);
    }

    onScroll();
    global.addEventListener('scroll', onScroll, { passive: true });
  }

  function initScrollSpy() {
    var links = $$('[data-spy]');
    if (!links.length || !global.IntersectionObserver) return;

    var sections = [];
    links.forEach(function (link) {
      var section = document.getElementById(link.getAttribute('data-spy'));
      if (section) sections.push(section);
    });
    if (!sections.length) return;

    var observer = new global.IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          links.forEach(function (link) {
            link.classList.toggle('is-active', link.getAttribute('data-spy') === entry.target.id);
          });
        });
      },
      { rootMargin: '-45% 0px -50% 0px', threshold: 0 }
    );

    sections.forEach(function (section) { observer.observe(section); });
  }

  function initSmoothScroll() {
    document.addEventListener('click', function (event) {
      var target = event.target;
      var link = null;
      while (target && target !== document) {
        if (target.tagName === 'A' && target.getAttribute('href')) {
          link = target;
          break;
        }
        target = target.parentNode;
      }
      if (!link) return;

      var href = link.getAttribute('href');
      if (href.charAt(0) !== '#' || href.length < 2) return;

      var section = document.getElementById(href.slice(1));
      if (!section) return;

      event.preventDefault();
      var top = section.getBoundingClientRect().top + (global.pageYOffset || 0) - navHeight() - 12;
      global.scrollTo({ top: top, behavior: reducedMotion() ? 'auto' : 'smooth' });
      if (global.history && global.history.replaceState) {
        global.history.replaceState(null, '', href);
      }
      document.dispatchEvent(new global.CustomEvent('mpvr:close-drawer'));
    });
  }

  /* -------------------------------------------------------------- copy -- */

  function copyWithFallback(text) {
    if (global.navigator && global.navigator.clipboard && global.navigator.clipboard.writeText) {
      return global.navigator.clipboard.writeText(text).catch(function () {
        return legacyCopy(text);
      });
    }
    return legacyCopy(text);
  }

  function legacyCopy(text) {
    return new global.Promise(function (resolve, reject) {
      var field = document.createElement('textarea');
      field.value = text;
      field.setAttribute('readonly', 'readonly');
      field.style.position = 'fixed';
      field.style.top = '-1000px';
      field.style.opacity = '0';
      document.body.appendChild(field);
      field.select();
      var ok = false;
      try {
        ok = document.execCommand('copy');
      } catch (err) {
        ok = false;
      }
      document.body.removeChild(field);
      if (ok) resolve();
      else reject(new Error('copy failed'));
    });
  }

  function initCopy() {
    $$('[data-copy]').forEach(function (button) {
      button.addEventListener('click', function () {
        var text = button.getAttribute('data-copy') || '';
        var label = button.querySelector('[data-copy-label]');
        var original = label ? label.textContent : '';

        copyWithFallback(text).then(
          function () {
            if (label) label.textContent = 'Copied';
            button.classList.add('is-copied');
            global.setTimeout(function () {
              if (label) label.textContent = original;
              button.classList.remove('is-copied');
            }, 1900);
          },
          function () {
            if (label) label.textContent = 'Press Ctrl+C';
            global.setTimeout(function () {
              if (label) label.textContent = original;
            }, 1900);
          }
        );
      });
    });
  }

  /* --------------------------------------------------- no alpine fallback -- */

  function initNoScriptFallbacks() {
    if (global.Alpine && global.Alpine.version) return;

    /* tabs */
    $$('[data-tabs]').forEach(function (group) {
      var buttons = $$('[data-tab]', group);
      var panels = $$('[data-tab-panel]', group);

      function select(index) {
        buttons.forEach(function (button, i) {
          button.classList.toggle('is-active', i === index);
          button.setAttribute('aria-selected', i === index ? 'true' : 'false');
        });
        panels.forEach(function (panel, i) {
          panel.removeAttribute('x-cloak');
          panel.classList.toggle('hidden', i !== index);
        });
      }

      buttons.forEach(function (button, i) {
        button.addEventListener('click', function () { select(i); });
      });
      select(0);
    });

    /* drawer */
    var toggle = $('[data-drawer-toggle]');
    var drawer = $('[data-drawer]');
    var scrim = $('[data-drawer-scrim]');
    if (toggle && drawer) {
      var open = function (state) {
        drawer.classList.toggle('is-open', state);
        if (scrim) scrim.classList.toggle('is-open', state);
        toggle.setAttribute('aria-expanded', state ? 'true' : 'false');
      };
      toggle.addEventListener('click', function () {
        open(!drawer.classList.contains('is-open'));
      });
      if (scrim) {
        scrim.addEventListener('click', function () { open(false); });
      }
      document.addEventListener('mpvr:close-drawer', function () { open(false); });
    }

    /* search box */
    var search = $('#bindings-search');
    if (search) {
      search.addEventListener('input', function () {
        BindingStore.setQuery(search.value);
      });
    }
  }

  /* ---------------------------------------------------------- bindings ui -- */

  function initBindingsUi() {
    BindingStore.subscribe(function () {
      renderBindingsPlain();
    });

    $$('#bindings-plain [data-sort]').forEach(function (header) {
      header.addEventListener('click', function () {
        BindingStore.toggleSort(header.getAttribute('data-sort'));
      });
    });
  }

  /* ------------------------------------------------------------- three.js -- */

  function initThree() {
    if (!global.MPVRThree || typeof global.MPVRThree.mount !== 'function') return;
    var host = $('#plate-canvas');
    if (!host) return;
    try {
      global.MPVRThree.mount(host, { frames: 4 });
    } catch (err) {
      /* the printed figures below the plate are the fallback */
    }
  }

  /* --------------------------------------------------------------- boot -- */

  function boot() {
    renderFeatures();
    renderConfigTree();
    renderInstallFlags();
    renderStatsFallback();
    renderFaqFallback();
    initBindingsUi();
    initNoScriptFallbacks();
    initReveal();
    initNav();
    initPlayhead();
    initScrollSpy();
    initSmoothScroll();
    initCopy();
    initThree();
    mountStatsAnt();
    mountFaqAnt();
    mountBindingsAnt();
  }

  /* -------------------------------------------------- alpine components -- */

  function registerAlpine() {
    if (!global.Alpine) return;

    global.Alpine.data('siteNav', function () {
      return {
        open: false,
        toggle: function () { this.open = !this.open; },
        close: function () { this.open = false; }
      };
    });

    global.Alpine.data('tabSet', function () {
      return {
        active: 0,
        select: function (index) { this.active = index; }
      };
    });

    global.Alpine.data('bindingsPanel', function () {
      return {
        query: '',
        total: DATA.keybindings.length,
        visible: DATA.keybindings.length,
        init: function () {
          var self = this;
          this.$watch('query', function (value) {
            BindingStore.setQuery(value);
          });
          BindingStore.subscribe(function () {
            self.query = BindingStore.query;
            self.visible = BindingStore.filtered().length;
          });
        },
        setQuery: function (value) { BindingStore.setQuery(value); },
        sortBy: function (key) { BindingStore.toggleSort(key); },
        mountAnt: function () { mountBindingsAnt(); }
      };
    });
  }

  document.addEventListener('alpine:init', registerAlpine);

  global.MPVRUI = {
    store: BindingStore,
    mountStatsAnt: mountStatsAnt,
    mountBindingsAnt: mountBindingsAnt,
    mountFaqAnt: mountFaqAnt
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () {
      global.setTimeout(boot, 0);
    });
  } else {
    global.setTimeout(boot, 0);
  }
})(window);
