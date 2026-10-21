/* ==========================================================================
   mpv-redesigned - the lamp above the hero
   --------------------------------------------------------------------------
   The hero sits in a dark room with one light in it. This is that light:
   a soft cone coming down from above the frame, with dust turning slowly
   inside the beam. There is no starfield and no floating glass planes.

   Design rules:
      * capped devicePixelRatio of 2, no antialias, additive blending only
      * requestAnimationFrame loop that stops when the tab is hidden
      * prefers-reduced-motion renders exactly one static frame
      * every geometry, material and the renderer itself are disposed on
        pagehide so nothing is left behind
   ========================================================================== */
(function (global) {
  'use strict';

  var reduceMotionQuery = global.matchMedia
    ? global.matchMedia('(prefers-reduced-motion: reduce)')
    : { matches: false, addEventListener: function () {} };

  function prefersReducedMotion() {
    return !!reduceMotionQuery.matches;
  }

  var LAMP = 0xe8b860;

  /* The beam.
     A cone is a shell, and a shell has no volume, so one cone would be
     invisible. Instead the beam is built from nested cones: a ray that runs
     close to the axis crosses every shell, and a ray near the edge crosses
     only the wide ones. Additively blended, that reads as a shaft of light.
     Each shell fades towards the floor, so the light dies before it lands. */
  function makeBeam(THREE, radius, height, opacity) {
    var group = new THREE.Group();
    var shells = 16;
    var i;

    for (i = 1; i <= shells; i += 1) {
      var r = radius * (i / shells);
      var geometry = new THREE.ConeGeometry(r, height, 48, 1, true);
      geometry.translate(0, -height / 2, 0);

      var material = new THREE.ShaderMaterial({
        uniforms: {
          uHeight: { value: height },
          uOpacity: { value: (opacity * (1 - i / shells) * 2.4) / shells },
          uColor: { value: new THREE.Color(LAMP) }
        },
        vertexShader: [
          'varying vec3 vPos;',
          'varying vec3 vNormal;',
          'varying vec3 vView;',
          'void main() {',
          '  vPos = position;',
          '  vec4 world = modelMatrix * vec4(position, 1.0);',
          '  vNormal = normalize(normalMatrix * normal);',
          '  vView = normalize(cameraPosition - world.xyz);',
          '  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);',
          '}'
        ].join('\n'),
        fragmentShader: [
          'uniform float uHeight;',
          'uniform float uOpacity;',
          'uniform vec3 uColor;',
          'varying vec3 vPos;',
          'varying vec3 vNormal;',
          'varying vec3 vView;',
          'void main() {',
          /* t is the distance from the point of the cone */
          '  float t = clamp(-vPos.y / uHeight, 0.0, 1.0);',
          /* brightest just under the lamp, gone by the floor */
          '  float along = smoothstep(0.0, 0.05, t) * pow(1.0 - t, 1.35);',
          /* fade the silhouette, otherwise every shell shows as a hard edge */
          '  float ndv = abs(dot(normalize(vNormal), normalize(vView)));',
          '  float soft = smoothstep(0.0, 0.45, ndv);',
          '  gl_FragColor = vec4(uColor, along * soft * uOpacity);',
          '}'
        ].join('\n'),
        transparent: true,
        depthWrite: false,
        blending: THREE.AdditiveBlending,
        side: THREE.DoubleSide
      });

      group.add(new THREE.Mesh(geometry, material));
    }

    return group;
  }

  /* Dust. Every mote is placed inside the cone so it is only ever visible
     where the light is, and it falls with the beam. */
  function makeMotes(THREE, count, radius, height, size, opacity) {
    var positions = new Float32Array(count * 3);
    var depth = new Float32Array(count);
    var angle = new Float32Array(count);
    var spread = new Float32Array(count);
    var speed = new Float32Array(count);
    var i;

    for (i = 0; i < count; i += 1) {
      depth[i] = 0.04 + Math.random() * 0.94;
      angle[i] = Math.random() * Math.PI * 2;
      spread[i] = Math.sqrt(Math.random()) * 0.8;
      speed[i] = 0.012 + Math.random() * 0.03;
      positions[i * 3] = 0;
      positions[i * 3 + 1] = 0;
      positions[i * 3 + 2] = 0;
    }

    var geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));

    var material = new THREE.PointsMaterial({
      color: LAMP,
      size: size,
      sizeAttenuation: true,
      transparent: true,
      opacity: opacity,
      depthWrite: false,
      blending: THREE.AdditiveBlending
    });

    var points = new THREE.Points(geometry, material);
    points.userData.depth = depth;
    points.userData.angle = angle;
    points.userData.spread = spread;
    points.userData.speed = speed;
    points.userData.radius = radius;
    points.userData.height = height;
    return points;
  }

  function mount(container, options) {
    var THREE = global.THREE;
    if (!THREE || !container) return null;

    var opts = options || {};
    var scene = new THREE.Scene();
    var camera = new THREE.PerspectiveCamera(55, 1, 0.1, 100);
    camera.position.set(0, 0, 7.6);

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
    container.appendChild(renderer.domElement);

    var coneRadius = 5.2;
    var coneHeight = 14;

    /* The lamp sits above the frame, a little to the right of centre, and
       the beam falls across the picture. */
    var beam = makeBeam(THREE, coneRadius, coneHeight, 0.13);
    beam.position.set(2.6, 3.2, -3.2);
    beam.rotation.z = 0.1;
    scene.add(beam);

    var moteCount = opts.points || 700;
    var motes = makeMotes(THREE, moteCount, coneRadius, coneHeight, 0.022, 0.3);
    motes.position.copy(beam.position);
    motes.rotation.z = 0.1;
    scene.add(motes);

    var clock = { last: 0 };
    var frame = null;
    var running = false;
    var disposed = false;

    function resize() {
      var rect = container.getBoundingClientRect();
      var width = Math.max(1, Math.round(rect.width || container.offsetWidth || 1));
      var height = Math.max(1, Math.round(rect.height || container.offsetHeight || 1));
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
      renderer.setSize(width, height, false);
    }

    function turn(elapsed) {
      var positions = motes.geometry.getAttribute('position');
      var depth = motes.userData.depth;
      var angle = motes.userData.angle;
      var spread = motes.userData.spread;
      var speed = motes.userData.speed;
      var radius = motes.userData.radius;
      var height = motes.userData.height;
      var array = positions.array;
      var i;

      for (i = 0; i < speed.length; i += 1) {
        /* the mote falls, and is carried around the axis on the way down */
        depth[i] += speed[i] * elapsed;
        if (depth[i] > 1) depth[i] -= 1;
        angle[i] += elapsed * 0.12;

        var r = radius * depth[i] * spread[i];
        array[i * 3] = Math.cos(angle[i]) * r;
        array[i * 3 + 1] = -depth[i] * height;
        array[i * 3 + 2] = Math.sin(angle[i]) * r;
      }
      positions.needsUpdate = true;
    }

    function render(timestamp) {
      if (disposed) return;
      var elapsed = clock.last ? (timestamp - clock.last) / 1000 : 0;
      clock.last = timestamp;

      turn(elapsed);
      beam.rotation.y += elapsed * 0.012;

      renderer.render(scene, camera);
    }

    function loop(timestamp) {
      if (!running || disposed) return;
      render(timestamp);
      frame = global.requestAnimationFrame(loop);
    }

    function start() {
      if (running || disposed) return;
      if (prefersReducedMotion()) {
        render(0);
        return;
      }
      running = true;
      clock.last = 0;
      frame = global.requestAnimationFrame(loop);
    }

    function stop() {
      running = false;
      if (frame) {
        global.cancelAnimationFrame(frame);
        frame = null;
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

      scene.traverse(function (object) {
        if (object.geometry && object.geometry.dispose) object.geometry.dispose();
        if (object.material && object.material.dispose) object.material.dispose();
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
      renderer: renderer
    };
  }

  global.MPVRThree = {
    mount: mount,
    prefersReducedMotion: prefersReducedMotion
  };
})(window);
