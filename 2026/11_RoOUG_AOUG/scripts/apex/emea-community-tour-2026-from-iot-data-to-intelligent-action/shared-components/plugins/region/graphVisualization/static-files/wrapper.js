function initializeGVT(
  regionId,
  containerId,
  ajaxId,
  displaySizeControl,
  templateSettings,
  templateStyles,
  settings,
  vertexLabel,
  edgeLabel,
  display,
  expand,
  fetchActions,
  persist,
  customHeight,
  updateGraphData,
  modesOptions,
  explorationOptions,
  pageItems,
  ruleBasedStyles,
  baseStyles,
  ruleBasedGroups,
  evolutionSettings,
  settingsThroughUi,
  schema,
  schemaSettings,
  defaultsForModes,
  searchFunction,
  enableExpand,
  updateRuleBasedStyle
) {
  let graphName;
  let graphOwner;
  let lastAppliedThemeKey;

  const createDeferredCallback = (callback) => {
    let pending = false;

    return () => {
      if (pending) {
        return;
      }

      pending = true;
      Promise.resolve().then(() => {
        pending = false;
        callback();
      });
    };
  };

  const hasExplicitVisualizationTheme = (currentSettings = {}) =>
    currentSettings.theme === 'light' || currentSettings.theme === 'dark';

  const hasCompleteCustomTheme = (currentSettings = {}) =>
    Boolean(currentSettings.customTheme?.backgroundColor && currentSettings.customTheme?.textColor);

  const installThemeMutationWatchers = (element, onMutation) => {
    if (typeof MutationObserver === 'undefined' || !element) {
      return undefined;
    }

    const mutationHandler = () => {
      onMutation();
    };

    const nodes = [element, document.documentElement, document.body].filter(Boolean);
    const observer = new MutationObserver(mutationHandler);
    nodes.forEach((node) => {
      observer.observe(node, {
        attributes: true,
        attributeFilter: ['class', 'style', 'data-theme', 'theme']
      });
    });

    let headObserver;
    if (document.head) {
      headObserver = new MutationObserver(mutationHandler);
      headObserver.observe(document.head, {
        childList: true,
        subtree: true,
        characterData: true,
        attributes: true,
        attributeFilter: ['href', 'media', 'disabled']
      });
    }

    return () => {
      observer.disconnect();
      headObserver?.disconnect();
    };
  };

  const fetchMore = (start, size) => {
    return new Promise((resolve, reject) => {
      apex.server.plugin(
        ajaxId,
        {
          x01: start,
          x02: size,
          pageItems: pageItems
        },
        {
          success: (graph) => {
            if (graph.vertices == null && graph.edges == null) {
              console.error('Query did not return any results. Vertices and edges are null.');
            } else {
              if (graph.edges != null) {
                graph.edges.forEach((e, i) => {
                  e.id = e.id == undefined ? i : e.id;
                });
              }
              if (graphName == null) {
                graphName = graph.graphName;
              }
              if (graphOwner == null) {
                graphOwner = graph.graphOwner;
              }
              resolve(graph);
            }
          },
          error: (e) => {
            console.error(e);
            reject(e);
          },
          dataType: 'json'
        }
      );
    });
  };

  const parse = (attribute) => {
    if (attribute) {
      try {
        return JSON.parse(attribute);
      } catch (e) {
        console.error(e);
      }
    }
    return {};
  };

  const target = document.getElementById(containerId);
  const numericHeight = Number(customHeight);
  if (numericHeight) {
    target.style.height = `${numericHeight}px`;
  } else {
    target.style.height = '400px';
  }

  const regionContainer = document.getElementById(regionId);

  const resolveHostThemeSettings = (baseSettings) => {
    if (hasExplicitVisualizationTheme(baseSettings) || hasCompleteCustomTheme(baseSettings) || !regionContainer) {
      return baseSettings;
    }

    const style = getComputedStyle(regionContainer);
    const hostBackgroundColor = style.getPropertyValue('--ut-region-background-color').trim() || style.backgroundColor;
    const hostTextColor = style.getPropertyValue('--ut-region-text-color').trim() || style.color;
    const backgroundColor = baseSettings.customTheme?.backgroundColor || hostBackgroundColor;
    const textColor = baseSettings.customTheme?.textColor || hostTextColor;

    if (!backgroundColor || !textColor) {
      return baseSettings;
    }

    return {
      ...baseSettings,
      customTheme: {
        backgroundColor,
        textColor
      }
    };
  };

  const getThemeSettingsKey = (baseSettings) => {
    const settingsWithTheme = resolveHostThemeSettings(baseSettings);
    return JSON.stringify({
      theme: settingsWithTheme.theme,
      backgroundColor: settingsWithTheme.customTheme?.backgroundColor,
      textColor: settingsWithTheme.customTheme?.textColor
    });
  };

  const updateHeight = () => {
    if (getComputedStyle(regionContainer).display === 'flex') {
      // Users can add multiple components within one region, making it difficult to calculate the height dynamically everywhere.
      // Check other plugins in APEX, such as the calendar, which does not have to fit everything in one screen. It is scrollable in fullscreen mode.
      target.style.height = '100%';
    } else {
      target.style.height = numericHeight ? `${numericHeight}px` : '400px';
    }
  };

  const observer = new MutationObserver(updateHeight);
  observer.observe(regionContainer, { attributes: true });

  target.addEventListener('click', (e) => {
    e.preventDefault();
  });

  const flags = new Set(display.split(':'));
  const modesOptionsFlags = new Set(modesOptions.split(':'));
  const explorationOptionsFlags = new Set(explorationOptions.split(':'));
  const defaultsForModesFlags = new Set(defaultsForModes.split(':'));

  const ALL_MODES_OPTIONS = ['interaction', 'fitToScreen', 'sticky', 'evolution'];
  const ALL_EXPLORATION_OPTIONS = ['expand', 'focus', 'group', 'ungroup', 'drop', 'undo', 'redo', 'reset'];
  const DEFAULTS_FOR_MODES = ['interactionActive', 'fitToScreenActive', 'stickyActive', 'evolutionActive'];

  const getFeatures = (allOptions, enabledOptions) => {
    return Object.fromEntries(allOptions.map((option) => [option, enabledOptions.has(option)]));
  };

  const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;

  const processSettings = () => {
    const parsedBaseStyles = baseStyles?.length > 0 ? parse(baseStyles) : {};
    const parsedTemplateStyles = templateStyles?.length > 0 ? parse(templateStyles) : {};
    const computedBaseStyles = { ...parsedBaseStyles, ...parsedTemplateStyles };

    const parsedTemplateSettings = parse(templateSettings);
    const parsedSettings = parse(settings);
    const parsedRuleBasedStyles = ruleBasedStyles?.length > 0 ? parse(ruleBasedStyles) : [];
    const parsedRuleBasedGroups = ruleBasedGroups?.length > 0 ? parse(ruleBasedGroups) : undefined;
    const parsedEvolutionSettings = evolutionSettings?.length > 0 ? parse(evolutionSettings) : undefined;
    const parsedSettingsThroughUi = parse(settingsThroughUi);

    let computedSettings = {
      ...parsedTemplateSettings,
      ...parsedSettings,
      ruleBasedStyles: parsedRuleBasedStyles,
      ...(Object.keys(computedBaseStyles).length > 0 && { baseStyles: computedBaseStyles }),
      ...(parsedRuleBasedGroups && { ruleBasedGroups: parsedRuleBasedGroups }),
      ...(parsedEvolutionSettings && { evolution: parsedEvolutionSettings }),
      ...parsedSettingsThroughUi
    };

    if (vertexLabel?.trim()?.length > 0) {
      _.set(computedSettings, 'baseStyles.vertex.label', `\${properties.${vertexLabel}}`);
    }
    if (edgeLabel?.trim()?.length > 0) {
      _.set(computedSettings, 'baseStyles.edge.label', `\${properties.${edgeLabel}}`);
    }

    computedSettings.defaults = getFeatures(DEFAULTS_FOR_MODES, defaultsForModesFlags);
    return computedSettings;
  };

  const updateThemeSettings = () => {
    if (!self) {
      return;
    }

    const nextThemeKey = getThemeSettingsKey(baseSettings);
    if (nextThemeKey === lastAppliedThemeKey) {
      return;
    }

    lastAppliedThemeKey = nextThemeKey;
    props.settings = resolveHostThemeSettings(baseSettings);
    self.$set({ settings: props.settings });
  };

  let baseSettings = processSettings();
  const props = {
    settings: resolveHostThemeSettings(baseSettings),
    featureFlags: {
      exploration: flags.has('exploration') ? getFeatures(ALL_EXPLORATION_OPTIONS, explorationOptionsFlags) : false,
      modes: flags.has('modes') ? getFeatures(ALL_MODES_OPTIONS, modesOptionsFlags) : false,
      displaySizeControl
    },
    schema: schema.trim() === '' ? undefined : parse(schema),
    schemaSettings: schemaSettings.trim() === '' ? undefined : parse(schemaSettings),
    fetchMore,
    expand: expand
      ? new AsyncFunction('ids', 'hops', expand)
      : enableExpand === 'Y'
      ? async (ids, numberOfHops) => {
          return new Promise((resolve, reject) => {
            apex.server.plugin(
              ajaxId,
              {
                x03: 'expand',
                f01: ids,
                x05: graphName,
                x06: graphOwner,
                x07: numberOfHops
              },
              {
                success: (result) => {
                  resolve(result);
                },
                error: (e) => {
                  console.error('Error executing expand PL/SQL block:', e);
                  reject(e);
                },
                dataType: 'json'
              }
            );
          });
        }
      : undefined,
    searchValueChanged: searchFunction ? new AsyncFunction('keyword', 'searchGraph', searchFunction) : undefined,
    fetchActions: new AsyncFunction(fetchActions),
    persist: new AsyncFunction('action', persist),
    updateGraphData: new AsyncFunction('vertices', 'edges', updateGraphData),
    updateRuleBasedStyle: updateRuleBasedStyle ? new AsyncFunction('style', 'action', updateRuleBasedStyle) : undefined,
    onManyClick: async (_, vertexColumnsArray, edgeColumnsArray) => {
      return new Promise((resolve, reject) => {
        apex.server.plugin(
          ajaxId,
          {
            x03: 'manylink',
            pageItems: pageItems,
            f02: vertexColumnsArray,
            f03: edgeColumnsArray
          },
          {
            success: (result) => {
              resolve(result); // Expect {vertexCount, edgeCount}
            },
            error: (e) => {
              console.error('Error fetching counts:', e);
              reject(e);
            },
            dataType: 'json'
          }
        );
      });
    }
  };

  let self = new GraphVisualization({
    target,
    props
  });
  lastAppliedThemeKey = getThemeSettingsKey(baseSettings);
  installThemeMutationWatchers(regionContainer, createDeferredCallback(updateThemeSettings));

  const createPlugin = () => {
    const eventTypes = ['graph', 'selection'];
    for (const type of eventTypes) {
      self.$on(type, (e) => {
        apex.event.trigger(target, type, e.detail);
      });
    }
    apex.region.create(regionId, { self, refresh });
  };

  const refresh = () => {
    baseSettings = processSettings();
    props.settings = resolveHostThemeSettings(baseSettings);
    self.$destroy();
    self = new GraphVisualization({
      target,
      props
    });
    lastAppliedThemeKey = getThemeSettingsKey(baseSettings);
    createPlugin();
  };

  createPlugin();
}
