import copy

from gnome.utilities.serializable import Serializable, Field
from gnome.persist.base_schema import ObjType


class NonWeatheringSubstance(Serializable):
    _state = copy.deepcopy(Serializable._state)
    _state += [Field('standard_density', update=True, read=True)]
    _schema = ObjType

    def __init__(self,
                 standard_density=1000.0,
                 pour_point=273.15):
        '''
        Non-weathering substance class for use with ElementType.
        - Right now, we consider our substance to have default properties
          similar to water, which we can of course change by passing something
          in.

        :param standard_density=1000.0: The density of the substance, assumed
                                        to be measured at 15 C.
        :type standard_density: Floating point decimal value

        :param pour_point=273.15: The pour_point of the substance, assumed
                                  to be measured in degrees Kelvin.
        :type pour_point: Floating point decimal value
        '''
        self.standard_density = standard_density
        self._pour_point = pour_point

    def pour_point(self):
        '''
            We need to match the interface of the OilProps object, so we
            define this as a read-only function
        '''
        return self._pour_point

    def density_at_temp(self):
        '''
            For non-weathering substance, we just return the standard density.
        '''
        return self.standard_density