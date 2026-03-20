const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'coosiik_crafting';

const state = {
  mode: null,
  stationKey: null,
  data: null,
  categoryKey: null,
  recipeKey: null,
  amount: 1,
  selectedBlueprint: null,
};

const app = document.getElementById('app');
const craftingView = document.getElementById('craftingView');
const blueprintView = document.getElementById('blueprintView');
const categoryList = document.getElementById('categoryList');
const recipeList = document.getElementById('recipeList');
const categoryTitle = document.getElementById('categoryTitle');
const categoryDescription = document.getElementById('categoryDescription');
const previewIcon = document.getElementById('previewIcon');
const stationTheme = document.getElementById('stationTheme');
const stationLabel = document.getElementById('stationLabel');
const recipeTitle = document.getElementById('recipeTitle');
const recipeDescription = document.getElementById('recipeDescription');
const recipeCategoryBadge = document.getElementById('recipeCategoryBadge');
const recipeDuration = document.getElementById('recipeDuration');
const recipeState = document.getElementById('recipeState');
const ingredientsList = document.getElementById('ingredientsList');
const skillList = document.getElementById('skillList');
const craftAmount = document.getElementById('craftAmount');
const craftButton = document.getElementById('craftButton');
const craftingProgress = document.getElementById('craftingProgress');
const blueprintCanvas = document.getElementById('blueprintCanvas');
const blueprintPoints = document.getElementById('blueprintPoints');
const skillPoints = document.getElementById('skillPoints');
const blueprintSkillList = document.getElementById('blueprintSkillList');
const blueprintDetails = document.getElementById('blueprintDetails');
const unlockBlueprintBtn = document.getElementById('unlockBlueprintBtn');

const nui = (eventName, body = {}) => fetch(`https://${resourceName}/${eventName}`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json; charset=UTF-8' },
  body: JSON.stringify(body),
});

window.addEventListener('message', ({ data }) => {
  if (data.action === 'open') {
    app.classList.remove('hidden');
    hydrate(data.payload);
  } else if (data.action === 'close') {
    closeUi();
  } else if (data.action === 'refresh') {
    if (state.data) {
      state.data = data.payload;
      render();
    }
  } else if (data.action === 'craftingState') {
    craftingProgress.classList.toggle('hidden', !data.active);
    craftingProgress.textContent = data.active ? 'Crafting in progress...' : '';
  }
});

function hydrate(payload) {
  state.mode = payload.mode;
  state.data = payload.data;
  state.stationKey = payload.stationKey || state.stationKey;

  if (state.mode === 'crafting') {
    const station = state.data.stations[state.stationKey];
    state.categoryKey = state.categoryKey && station.categories.some(cat => cat.key === state.categoryKey)
      ? state.categoryKey
      : station.categories[0]?.key;
    const recipes = getVisibleRecipes();
    state.recipeKey = recipes.find(recipe => recipe.key === state.recipeKey)?.key || recipes[0]?.key || null;
  }

  if (state.mode === 'blueprints' && !state.selectedBlueprint) {
    state.selectedBlueprint = state.data.blueprintTree[0]?.key || null;
  }

  render();
}

function render() {
  craftingView.classList.toggle('hidden', state.mode !== 'crafting');
  blueprintView.classList.toggle('hidden', state.mode !== 'blueprints');

  if (state.mode === 'crafting') renderCrafting();
  if (state.mode === 'blueprints') renderBlueprints();
}

function getVisibleRecipes() {
  const recipes = Object.values(state.data.recipes || {});
  return recipes
    .filter(recipe => recipe.station === state.stationKey && recipe.category === state.categoryKey)
    .sort((a, b) => a.label.localeCompare(b.label));
}

function renderCrafting() {
  const station = state.data.stations[state.stationKey];
  stationTheme.textContent = station.theme.charAt(0).toUpperCase() + station.theme.slice(1);
  stationLabel.textContent = station.label;

  categoryList.innerHTML = '';
  station.categories.forEach(category => {
    const button = document.createElement('button');
    button.className = `category-pill ${state.categoryKey === category.key ? 'active' : ''}`;
    button.textContent = category.icon;
    button.title = category.label;
    button.onclick = () => {
      state.categoryKey = category.key;
      state.recipeKey = getVisibleRecipes()[0]?.key || null;
      renderCrafting();
    };
    categoryList.appendChild(button);
  });

  const activeCategory = station.categories.find(category => category.key === state.categoryKey) || station.categories[0];
  categoryTitle.textContent = activeCategory?.label || '';
  categoryDescription.textContent = activeCategory?.description || '';

  const recipes = getVisibleRecipes();
  if (!recipes.some(recipe => recipe.key === state.recipeKey)) state.recipeKey = recipes[0]?.key || null;

  recipeList.innerHTML = '';
  recipes.forEach(recipe => {
    const button = document.createElement('button');
    button.className = `recipe-card ${state.recipeKey === recipe.key ? 'selected' : ''}`;
    button.innerHTML = `
      <div class="recipe-icon">${recipe.icon}</div>
      <div class="recipe-name">${recipe.label}</div>
      <div class="recipe-meta">${recipe.blueprintKnown ? 'Unlocked' : 'Research required'} • ${recipe.durationLabel}</div>
    `;
    button.onclick = () => {
      state.recipeKey = recipe.key;
      renderCrafting();
    };
    recipeList.appendChild(button);
  });

  const recipe = state.data.recipes[state.recipeKey];
  if (!recipe) return;

  previewIcon.textContent = recipe.icon;
  recipeTitle.textContent = recipe.label;
  recipeDescription.textContent = recipe.description;
  recipeCategoryBadge.textContent = recipe.category;
  recipeDuration.textContent = recipe.durationLabel;

  const unlocked = recipe.unlocked;
  recipeState.textContent = unlocked ? 'UNLOCKED' : (recipe.blueprintKnown ? 'LOCKED' : 'RESEARCH REQUIRED');
  recipeState.className = `badge state ${unlocked ? 'unlocked' : 'locked'}`;

  ingredientsList.innerHTML = '';
  recipe.ingredients.forEach(ingredient => {
    const row = document.createElement('div');
    row.className = 'requirement';
    row.innerHTML = `
      <div>
        <div>${ingredient.label}</div>
        <div class="subtitle">${ingredient.item}</div>
      </div>
      <div class="value ${ingredient.met ? 'ok' : 'bad'}">${ingredient.have}/${ingredient.count}</div>
    `;
    ingredientsList.appendChild(row);
  });

  skillList.innerHTML = '';
  Object.entries(state.data.skillTree || {}).forEach(([skillKey, skill]) => {
    const current = state.data.player.skills[skillKey] || 0;
    const row = document.createElement('div');
    row.className = 'skill-row';
    row.innerHTML = `
      <div>
        <div>${skill.label}</div>
        <div class="subtitle">${current}/${skill.maxLevel}</div>
      </div>
      <button class="skill-upgrade">+1</button>
    `;
    row.querySelector('button').onclick = () => nui('upgradeSkill', { skill: skillKey });
    skillList.appendChild(row);
  });

  craftAmount.textContent = `${state.amount}x`;
  craftButton.textContent = unlocked ? 'CRAFT' : 'LOCKED';
  craftButton.className = `craft-button ${unlocked ? '' : 'locked'}`;
  craftButton.disabled = !unlocked;
}

function renderBlueprints() {
  blueprintPoints.textContent = `Blueprint points: ${state.data.player.blueprintPoints || 0}`;
  skillPoints.textContent = `Skill points: ${state.data.player.unspentPoints || 0}`;

  blueprintSkillList.innerHTML = '';
  Object.entries(state.data.skillTree || {}).forEach(([skillKey, skill]) => {
    const current = state.data.player.skills[skillKey] || 0;
    const row = document.createElement('div');
    row.className = 'skill-row';
    row.innerHTML = `
      <div>
        <div>${skill.label}</div>
        <div class="subtitle">${current}/${skill.maxLevel}</div>
      </div>
      <button class="skill-upgrade">+1</button>
    `;
    row.querySelector('button').onclick = () => nui('upgradeSkill', { skill: skillKey });
    blueprintSkillList.appendChild(row);
  });

  blueprintCanvas.innerHTML = '';
  drawConnectors();

  state.data.blueprintTree.forEach(node => {
    const element = document.createElement('button');
    element.className = `blueprint-node ${node.unlocked ? 'unlocked' : (node.available ? '' : 'locked')} ${state.selectedBlueprint === node.key ? 'selected' : ''}`;
    element.style.left = `${node.position.x}%`;
    element.style.top = `${node.position.y}%`;
    element.innerHTML = `
      <div class="node-title">${node.label}</div>
      <div class="node-group">${node.group}</div>
      <div class="subtitle">${node.description}</div>
      <div class="node-cost">Cost: ${node.cost}</div>
    `;
    element.onclick = () => {
      state.selectedBlueprint = node.key;
      renderBlueprints();
    };
    blueprintCanvas.appendChild(element);
  });

  const selected = state.data.blueprintTree.find(node => node.key === state.selectedBlueprint) || state.data.blueprintTree[0];
  if (!selected) return;

  state.selectedBlueprint = selected.key;
  blueprintDetails.innerHTML = `
    <div><strong>${selected.label}</strong></div>
    <div class="subtitle">${selected.description}</div>
    <div class="top-gap">Powiazane receptury: ${(selected.recipeKeys || []).join(', ') || 'brak'}</div>
    <div class="top-gap">Wymaga: ${(selected.requires || []).join(', ') || 'brak'}</div>
    <div class="top-gap">Status: ${selected.unlocked ? 'Unlocked' : (selected.available ? 'Available' : 'Locked')}</div>
  `;

  unlockBlueprintBtn.disabled = selected.unlocked || !selected.available;
  unlockBlueprintBtn.className = `craft-button secondary ${selected.unlocked || !selected.available ? 'locked' : ''}`;
  unlockBlueprintBtn.textContent = selected.unlocked ? 'UNLOCKED' : 'UNLOCK RESEARCH';
}

function drawConnectors() {
  const map = Object.fromEntries(state.data.blueprintTree.map(node => [node.key, node]));

  state.data.blueprintTree.forEach(node => {
    (node.requires || []).forEach(requiredKey => {
      const parent = map[requiredKey];
      if (!parent) return;
      const connector = document.createElement('div');
      connector.className = 'connector';
      const x1 = parent.position.x;
      const y1 = parent.position.y;
      const x2 = node.position.x;
      const y2 = node.position.y;
      const dx = x2 - x1;
      const dy = y2 - y1;
      const length = Math.sqrt(dx * dx + dy * dy);
      const angle = Math.atan2(dy, dx) * 180 / Math.PI;
      connector.style.left = `${x1}%`;
      connector.style.top = `${y1}%`;
      connector.style.width = `${length}%`;
      connector.style.transform = `rotate(${angle}deg)`;
      blueprintCanvas.appendChild(connector);
    });
  });
}

function closeUi() {
  app.classList.add('hidden');
  craftingView.classList.add('hidden');
  blueprintView.classList.add('hidden');
}

document.querySelectorAll('[data-amount]').forEach(button => {
  button.addEventListener('click', () => {
    if (button.dataset.amount === 'up') state.amount = Math.min(10, state.amount + 1);
    if (button.dataset.amount === 'down') state.amount = Math.max(1, state.amount - 1);
    craftAmount.textContent = `${state.amount}x`;
  });
});

craftButton.addEventListener('click', () => {
  if (!state.recipeKey) return;
  nui('craft', { recipeKey: state.recipeKey, amount: state.amount });
});

unlockBlueprintBtn.addEventListener('click', () => {
  if (!state.selectedBlueprint) return;
  nui('unlockBlueprint', { nodeKey: state.selectedBlueprint });
});

document.addEventListener('keydown', event => {
  if (event.key === 'Escape') {
    nui('close');
  }
});
