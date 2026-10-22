/* ==========================================================================
   mpv-redesigned - the light table
   --------------------------------------------------------------------------
   One dark plate in the middle of a paper document. Inside it, the four
   stills turn slowly on a shallow arc, the way frames turn on a light table.

   Design rules:
      * capped devicePixelRatio of 2, no antialias
      * requestAnimationFrame loop that stops when the tab is hidden
      * prefers-reduced-motion renders exactly one static frame
      * every geometry, material, texture and the renderer itself are
        disposed on pagehide so nothing is left behind
      * if the images or WebGL are unavailable, the printed figures under
        the plate are the fallback and the page still reads
   ========================================================================== */
(function (global) {
  'use strict';

  var reduceMotionQuery = global.matchMedia
    ? global.matchMedia('(prefers-reduced-motion: reduce)')
    : { matches: false, addEventListener: function () {} };

  function prefersReducedMotion() {
    return !!reduceMotionQuery.matches;
  }

  var FRAMES = [
    { src: 'assets/images/control-bar.png', title: 'The Liquid Glass control bar' },
    { src: 'assets/images/format-picker.png', title: 'The format picker' },
    { src: 'assets/images/load-media-menu.png', title: 'The load-media browser' },
    { src: 'assets/images/hero-idle.jpg', title: 'The idle screen' }
  ];

  var WIDTH = 4.2;
  var HEIGHT = 2.52;
  var RADIUS = 7;
  var SPREAD = 0.42;

  function mount(container, options) {
    var THREE = global.THREE;
    if (!THREE || !container) return null;

    var opts = options || {};
    var count = opts.frames || FRAMES.length;

    var scene = new THREE.Scene();
    var camera = new THREE.PerspectiveCamera(30, 1, 0.1, 100);
    camera.position.set(0, 0.1, 9.2);

    var renderer;
    try {
      renderer = new THREE.WebGLRenderer({
        alpha: true,
        antialias: false,
        powerPreference: 'low-power'
      });
    } catch (err) {
      return null;
    }

    renderer.setClearColor(0x000000, 0);
    renderer.setPixelRatio(Math.min(global.devicePixelRatio || 1, 2));
    renderer.domElement.setAttribute('aria-hidden', 'true');
    renderer.domElement.style.width = '100%';
    renderer.domElement.style.height = '100%';
    renderer.domElement.style.touchAction = 'pan-y';
    container.appendChild(renderer.domElement);

    var group = new THREE.Group();
    scene.add(group);

    /* The frames. Each one is a mount with a border and the picture on it. */
    var loader = new THREE.TextureLoader();
    var loaded = 0;
    var planes = [];

    for (var i = 0; i < count; i += 1) {
      var frame = FRAMES[i % FRAMES.length];
      var angle = (i - (count - 1) / 2) * SPREAD;

      var mountGeo = new THREE.PlaneGeometry(WIDTH + 0.22, HEIGHT + 0.22);
      var mountMat = new THREE.MeshBasicMaterial({
        color: 0x2b2e32,
        transparent: true,
        opacity: 0
      });
      var back = new THREE.Mesh(mountGeo, mountMat);
      back.position.set(
        Math.sin(angle) * RADIUS,
        0,
        Math.cos(angle) * RADIUS - RADIUS
      );
      back.rotation.y = -angle;
      group.add(back);

      var geo = new THREE.PlaneGeometry(WIDTH, HEIGHT);
      var mat = new THREE.MeshBasicMaterial({
        color: 0xffffff,
        transparent: true,
        opacity: 0
      });
      var plane = new THREE.Mesh(geo, mat);
      plane.position.copy(back.position);
      plane.rotation.y = -angle;
      group.add(plane);

      planes.push({ back: back, face: plane, angle: angle });

      (function (index, backMesh, faceMesh, backMaterial, faceMaterial) {
        loader.load(
          frame.src,
          function (texture) {
            texture.colorSpace = THREE.SRGBColorSpace;
            texture.minFilter = THREE.LinearFilter;
            texture.generateMipmaps = false;
            faceMaterial.map = texture;
            faceMaterial.needsUpdate = true;
            loaded += 1;
            faceMaterial.opacity = 1;
            backMaterial.opacity = 1;
            /* with reduced motion the loop never runs, so the one still
               frame has to be redrawn now that the picture is there */
            if (!running) render(0);
          },
          undefined,
          function () {
            /* the frame stays blank; the printed figures below carry it */
          }
        );
      })(i, back, plane, mountMat, mat);
    }

    /* The scrubber: drag the arc round. */
    var drag = { active: false, x: 0, last: 0, offset: 0, velocity: 0 };
    var spin = 0;

    function onDown(event) {
      drag.active = true;
      drag.last = event.clientX;
      drag.velocity = 0;
      renderer.domElement.style.cursor = 'grabbing';
    }

    function onMove(event) {
      if (!drag.active) return;
      var dx = event.clientX - drag.last;
      drag.last = event.clientX;
      drag.offset += dx * 0.005;
      drag.velocity = dx * 0.005;
    }

    function onUp() {
      drag.active = false;
      renderer.domElement.style.cursor = 'grab';
    }

    renderer.domElement.style.cursor = 'grab';
    renderer.domElement.addEventListener('pointerdown', onDown);
    global.addEventListener('pointermove', onMove);
    global.addEventListener('pointerup', onUp);
    global.addEventListener('pointercancel', onUp);

    var clock = { last: 0 };
    var frameId = null;
    var running = false;
    var disposed = false;

    function resize() {
      var rect = container.getBoundingClientRect();
      var width = Math.max(1, Math.round(rect.width || container.offsetWidth || 1));
      var height = Math.max(1, Math.round(rect.height || container.offsetHeight || 1));
      camera.aspect = width / height;

      /* Frame the arc whatever shape the plate is: the widest frame sits
         half a width outside the outer edge of the arc. */
      var maxAngle = ((count - 1) / 2) * SPREAD;
      var halfSpan = Math.sin(maxAngle) * RADIUS + WIDTH / 2;
      var halfHeight = HEIGHT / 2;
      var vFov = (camera.fov * Math.PI) / 180;
      var forWidth = halfSpan / (Math.tan(vFov / 2) * camera.aspect);
      var forHeight = halfHeight / Math.tan(vFov / 2);

      camera.position.set(0, 0.05, Math.max(forWidth, forHeight) + 1.1);
      camera.lookAt(0, 0, 0);
      camera.updateProjectionMatrix();
      renderer.setSize(width, height, false);
    }

    function render(timestamp) {
      if (disposed) return;
      var elapsed = clock.last ? (timestamp - clock.last) / 1000 : 0;
      clock.last = timestamp;

      /* the table breathes; a drag nudges it and it settles back */
      if (!drag.active) {
        drag.velocity *= 0.94;
        drag.offset += drag.velocity;
        drag.offset *= 0.985;
      }
      spin += elapsed * 0.085;

      group.rotation.y = spin + drag.offset;
      group.position.y = Math.sin(spin * 0.7) * 0.16;

      for (var i = 0; i < planes.length; i += 1) {
        var depth = Math.cos(planes[i].angle) * RADIUS;
        var lift = 1 - depth / RADIUS;
        planes[i].face.position.y = planes[i].back.position.y + lift * 0.06;
        planes[i].face.rotation.z = planes[i].back.rotation.z = Math.sin(spin * 0.5 + i) * 0.004;
      }

      renderer.render(scene, camera);
    }

    function loop(timestamp) {
      if (!running || disposed) return;
      render(timestamp);
      frameId = global.requestAnimationFrame(loop);
    }

    function start() {
      if (running || disposed) return;
      if (prefersReducedMotion()) {
        render(0);
        return;
      }
      running = true;
      clock.last = 0;
      frameId = global.requestAnimationFrame(loop);
    }

    function stop() {
      running = false;
      if (frameId) {
        global.cancelAnimationFrame(frameId);
        frameId = null;
      }
    }

    function onVisibility() {
      if (document.hidden) {
        stop();
      } else {
        start();
      }
    }

    function dispose() {
      if (disposed) return;
      disposed = true;
      stop();
      document.removeEventListener('visibilitychange', onVisibility);
      global.removeEventListener('resize', resize);
      global.removeEventListener('pagehide', dispose);
      global.removeEventListener('pointermove', onMove);
      global.removeEventListener('pointerup', onUp);
      global.removeEventListener('pointercancel', onUp);

      scene.traverse(function (object) {
        if (object.geometry && object.geometry.dispose) object.geometry.dispose();
        if (object.material && object.material.dispose) object.material.dispose();
        if (object.material && object.material.map && object.material.map.dispose) {
          object.material.map.dispose();
        }
      });
      scene.clear();
      if (renderer.domElement && renderer.domElement.parentNode) {
        renderer.domElement.parentNode.removeChild(renderer.domElement);
      }
      if (renderer.dispose) renderer.dispose();
      if (renderer.forceContextLoss) renderer.forceContextLoss();
    }

    resize();
    global.addEventListener('resize', resize);
    document.addEventListener('visibilitychange', onVisibility);
    global.addEventListener('pagehide', dispose);

    if (prefersReducedMotion()) {
      render(0);
    } else {
      start();
    }

    return {
      start: start,
      stop: stop,
      dispose: dispose,
      renderer: renderer,
      loaded: function () { return loaded; }
    };
  }

  global.MPVRThree = {
    mount: mount,
    prefersReducedMotion: prefersReducedMotion
  };
})(window);
